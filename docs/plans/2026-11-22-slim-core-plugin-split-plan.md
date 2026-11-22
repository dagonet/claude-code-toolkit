# Slim Core Plugin Split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `cct` keeps only the PO/T1-T4 workflow, safety and their plumbing. Everything else moves, unchanged in behaviour, into four optional plugins (`cct-jev`, `cct-learning`, `cct-guards`, `cct-helpers`) and the language plugins.

**Architecture:**
- **Self-contained plugins.** Each optional plugin is a folder under `plugins/` with its own `.claude-plugin/plugin.json`, and its own `hooks/hooks.json` if it has hooks.
- **Hook plumbing.** A plugin with hooks carries pinned copies of `run-hook.sh` and the `hooks/lib/` files it uses, plus its own small `hook-class.sh` table.
- **Language coders** move into the existing `plugins/<lang>-tools`, and a new `plugins/java-tools`. The core helpers learn their names from one fixed table.
- **Challenge.** The challenge command becomes a core T3/T4 step.

**Tech Stack:** bash hooks, JSON plugin manifests, Markdown agents/skills/templates, Python (Jev and its tests), the existing test scripts.

**Spec:** `docs/plans/2026-11-22-slim-core-plugin-split-design.md`, approved 2026-11-22 19:24. §10 is binding. The decisions table in §2 records the challenge step and the language coders.

## Global Constraints

- **Branch and release:**
  - work on `feat/v6.3`, worktree `~/git/.worktrees/claude-code-toolkit/v6.3`;
  - ships inside **v7.0.0** (user rulings 20:09 and 20:12), built after the backlog-discipline plan;
  - every plugin's `version` equals `VERSION`. Check 72 already scans `plugins/*/.claude-plugin/plugin.json`.
- **Nothing is deleted.** Every moved file keeps its behaviour, and its tests move with it and stay green.
- **Plugin names:** `cct-jev`, `cct-learning`, `cct-guards`, `cct-helpers`, `java-tools`. All are added to `.claude-plugin/marketplace.json` with a one-line description that starts "Optional:".
- **What moves (exact):**

  | Plugin | Hooks | Skills | Agents |
  |---|---|---|---|
  | `cct-jev` | `jev-route`, `jev-notice` | `jev` (with `.py` files and `tests/`) | — |
  | `cct-learning` | `retro-ledger`, `retro-brief` | `retro-review` | — |
  | `cct-guards` | `read-size-gate`, `bash-output-guard`, `agent-budget-warn`, `post-edit-build` | — | — |
  | `cct-helpers` | — | `commit`, `contribute-upstream`, `karpathy-guidelines`, `mcp-usage` | — |
  | `dotnet-tools` | — | — | `dotnet-coder` |
  | `python-tools` | — | — | `python-coder` |
  | `rust-tools` | — | — | `rust-coder` |
  | `java-tools` (new) | — | — | `java-coder` |
- **Stays in `cct`:**
  - agents `coder`, `code-reviewer`, `tester`, `architect`, `Explore`, `ops`;
  - skills `sprint`, `challenge`, `sync-template`;
  - all other hooks, `hooks/lib/`, `output-styles/`, templates, server and scripts.
- **Pinned copies:** each optional plugin's `hooks/run-hook.sh` and `hooks/lib/<f>.sh` copies are byte-identical to `cct`'s. `hook-class.sh` is per plugin, lists only its own hooks, and is excluded from the identity check.
- **Hook class and polarity** of every moved hook are unchanged (copy its `hc_class` line verbatim).
- **Language coder table** (exact): `dotnet-tools:dotnet-coder`, `python-tools:python-coder`, `rust-tools:rust-coder`, `java-tools:java-coder`. Each maps to `model` and `pipeline` read from that agent file's frontmatter today. A check pins the table against the files.
- **Jev marker:** `cct-jev` writes its own SessionStart marker. `model-floor` steps aside only when the switch says `"route": true` **and** this session has the `cct-jev` marker, so a missing plugin means the floor applies.
- **"If installed" wording:** every template, rule, agent or skill mention of a moved part says "if `<plugin>` is installed".
- **Release notes:** they carry the old-to-new name map. `sync-template` warns, and does not edit, on old names in kept project files.
- **Experiments:** `claude plugin` and installer experiments only with `HOME=$(mktemp -d)` and `env -u CLAUDE_CONFIG_DIR`. Never copy credentials, and never touch the live `~/.claude`.
- **Files:** LF only. `AGENT_TEAM.md` and `.claude/settings.json` stay byte-identical across the six variants.
- **KISS:** no new mechanism beyond copies plus checks. Prefer moving files with `git mv`.

## Review Focus

1. **`cct` installed alone** (temp HOME): no hook registration points at a moved script; every remaining hook runs; a project from each variant passes its first commit. Task 8.
2. **`cct-guards` installed but `cct` not:** its hooks must still run (own `run-hook.sh` and libs), or fail as their polarity says, never with "file not found" on a `cct` path. Task 3.
3. **A language coder spawn with only `cct` plus `dotnet-tools`:** the model floor and the report contract still apply (fixed table). Task 1.
4. **Jev switch on, `cct-jev` uninstalled:** `model-floor` floors (it does not step aside). Task 5.
5. **A consumer project naming `cct:dotnet-coder` after the update:** `sync-template` warns with the new name. Task 8.

---

### Task 1: Language coders move to the language plugins

**Files:**
- `git mv agents/{dotnet,python,rust,java}-coder.md` to `plugins/<lang>-tools/agents/`.
- Create `plugins/java-tools/.claude-plugin/plugin.json` (agent only, no `.mcp.json`), plus a marketplace entry.
- Modify:
  - `hooks/lib/agent-model.sh` (`am_resolve`: the fixed table for the four types);
  - `hooks/enforce-agent-contract.sh` (the same table for the pipeline flag);
  - `hooks/enforce-delegation.sh` (named types);
  - `templates/<six>/CLAUDE.md` team tables (`cct:<lang>-coder` becomes `cct:coder` plus "prefer `<lang>-tools:<lang>-coder` if installed");
  - `templates/general/AGENT_TEAM.md`, then `cp`;
  - `setup-project.sh` / `.ps1` (each language variant's default Test/Gate suggestion includes its format check, e.g. `dotnet format --verify-no-changes`);
  - `scripts/verify-template-consistency.sh` (new check: table equals the agent frontmatter; plugin agents carry no `hooks:`, which extends check 75 to `plugins/*/agents`);
  - `scripts/test-hooks.sh`.

- [ ] **Step 1: Failing rows.**
  - A `dotnet-tools:dotnet-coder` spawn with no model gets the table's model from `model-floor`.
  - Its final report without the contract lines gets the contract refusal.
  - An unknown `foo-tools:foo-coder` gets no change.
  - The consistency table check, with a control that edits one frontmatter model.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Move and implement.**
- [ ] **Step 4: Run** test-hooks (full, foreground) and the consistency script. Expected: 0 FAIL, PASS. Then run `bash scripts/test-setup-project.sh`. Expected: PASS.
- [ ] **Step 5: Commit** `feat!: language coders move into the language plugins; core resolves them by a fixed table`.

### Task 2: Plugin skeletons and the pinned-copy check

**Files:**
- Create `plugins/{cct-jev,cct-learning,cct-guards,cct-helpers}/.claude-plugin/plugin.json` (version = `VERSION`).
- Add marketplace entries.
- Add one consistency check, `pinned plugin copies`. For every `plugins/*/hooks/run-hook.sh` and `plugins/*/hooks/lib/*.sh`, except `hook-class.sh`, it asserts byte-identity with `hooks/<same path>`. Two-sided: a control copy with one changed byte is flagged.

- [ ] **Step 1:** Add the check (vacuous-pass guard: it fails if it scanned zero files once Task 3 lands; until then it reports "0 copies"). Run. Expected: PASS with 0 copies.
- [ ] **Step 2:** Create the four manifests and marketplace entries. `claude plugin validate` on each in a temp HOME. Expected: no errors.
- [ ] **Step 3: Commit** `feat: optional plugin skeletons (cct-jev, cct-learning, cct-guards, cct-helpers) and the pinned-copy check`.

### Task 3: Move `cct-guards`

**Files:**
- `git mv hooks/{read-size-gate,bash-output-guard,agent-budget-warn,post-edit-build}.sh` to `plugins/cct-guards/hooks/`.
- Copy `run-hook.sh` and `lib/{json.sh,git-cmd.sh}` (plus whatever those source).
- Create `plugins/cct-guards/hooks/lib/hook-class.sh` (the four lines) and `plugins/cct-guards/hooks/hooks.json` (the four registrations exactly as they are in `hooks/hooks.json` today).
- Modify:
  - `hooks/hooks.json` (remove the four);
  - `hooks/lib/hook-class.sh` (remove the four);
  - the root `.claude/settings.json` `post-edit-build` path;
  - check 71 and check 74 lists;
  - `scripts/test-hooks.sh` (paths);
  - "if installed" wording: `user-level-reference/CLAUDE.md` (Read & Search), the agents' `agent-budget-warn` mentions, `templates/general/PROJECT_CONTEXT.md` (`Post-edit build`), and `skills/sync-template/SKILL.md`.

- [ ] **Step 1: Failing rows.**
  - Each moved hook runs from `plugins/cct-guards/hooks/run-hook.sh <name>` with the same verdicts as before (Review Focus 2).
  - `cct`'s `hooks.json` has no registration for them.
- [ ] **Step 2: Move and implement.** Run test-hooks (full) and the consistency script. Expected: 0 FAIL, PASS. Check 35 still passes after the user-level wording.
- [ ] **Step 3: Commit** `feat!: cost and context guards move to the optional cct-guards plugin`.

### Task 4: Move `cct-learning`

Same shape as Task 3:
- `retro-ledger` and `retro-brief` hooks;
- `skills/retro-review` → `plugins/cct-learning/skills/retro-review`;
- the `AGENT_TEAM.md` retro-ledger line becomes "if `cct-learning` is installed".

Commit `feat!: the learning loop moves to the optional cct-learning plugin`.

### Task 5: Move `cct-jev`

**Files:**
- `git mv skills/jev` → `plugins/cct-jev/skills/jev`, and `hooks/{jev-route,jev-notice}.sh` → `plugins/cct-jev/hooks/`.
- Copy the libs, including `agent-model.sh`.
- Create the `cct-jev` session-marker hook: its own marker name, written and cleared like `cct-session.sh`.
- Modify:
  - `hooks/lib/agent-model.sh` `am_jev_routing`: it requires the `cct-jev` marker for this session, instead of checking `cct`'s own `skills/jev/jev_route.py`;
  - where the Jev Python tests run (locate by content and update paths);
  - `skills/jev/SKILL.md` command paths (`${CLAUDE_PLUGIN_ROOT}` now means `cct-jev`'s root).

- [ ] **Step 1: Failing rows.**
  - Switch on with the `cct-jev` marker: the floor steps aside.
  - Switch on with no marker: the floor applies (Review Focus 4).
  - Switch off: the floor applies.
  - The Jev Python tests run green from the new path.
- [ ] **Step 2: Implement.** Run test-hooks (full), the Jev tests and the consistency script. Expected: all green.
- [ ] **Step 3: Commit** `feat!: Jev moves to the optional cct-jev plugin; the floor steps aside only when cct-jev is loaded`.

### Task 6: Move `cct-helpers`

`git mv skills/{commit,contribute-upstream,karpathy-guidelines,mcp-usage}` to `plugins/cct-helpers/skills/`.

"If installed" wording in:
- `user-level-reference/CLAUDE.md` (the karpathy line);
- `templates/general/PROJECT_CONTEXT.md` and `.claude/project-instructions.md` (`mcp-usage`);
- the agents' `## Skills` tables;
- `skills/commit` mentions in other skills.

Run the consistency script. Expected: PASS. Commit `feat!: small helper skills move to the optional cct-helpers plugin`.

### Task 7: Challenge becomes a core T3/T4 step

**Files:**
- `skills/challenge/SKILL.md` (remove `disable-model-invocation: true`);
- `templates/general/AGENT_TEAM.md`, then `cp`:
  - the "Challenging a plan is optional and on demand" line becomes "T3 and T4: the plan is challenged (`challenge` skill) before coding starts; at T4 the architect runs it as part of its design review.";
  - the checkpoint table gains a row `Plan challenged | — | — | Yes | Yes`;
- `skills/sprint/SKILL.md` (T3/T4 tasks run the challenge before dispatch);
- a consistency assertion for the new checkpoint row.

Commit `feat: the plan challenge is a required T3/T4 step`.

### Task 8: Installer, delivery check, sync warning, install tests, docs

**Files:**
- `scripts/install-user-level-linux.sh` (`--with <plugin,...>`; installs nothing optional by default);
- `scripts/verify-user-level-drift.sh`:
  - an informational list of installed optional plugins;
  - drift only when `enabledPlugins` names a plugin not installed at `VERSION`;
- `skills/sync-template/SKILL.md`: a step that warns on old names (`cct:<lang>-coder`, `/cct:jev`, `/cct:commit`, `/cct:retro-review`, `cct:karpathy-guidelines`, `cct:mcp-usage`) in kept project files, naming the new one;
- `docs/architecture.md`, `README.md`, `docs/verification.md`, `CHANGELOG.md` (v7.0.0 notes: the name map, one install line per plugin, the plain-update warning);
- a new `scripts/test-plugin-split.sh`, called from the consistency script.

`scripts/test-plugin-split.sh`, in a temp HOME:
- add the repo as a local marketplace;
- install `cct` alone. Assert no registered command path names a moved script, and bootstrap one project per variant with `setup-project.sh`; its first commit passes (Review Focus 1);
- install everything. Assert the union of hook registrations equals the pre-split set (a fixture list captured in Task 2 from `hooks/hooks.json` at `36d121f`).

- [ ] **Step 1:** Write the test, and see the "everything" assert fail until all moves are in (they are, by now). Run it. Expected: PASS.
- [ ] **Step 2:** Installer, drift and sync changes, with test rows for `--with` parsing and the drift rule.
- [ ] **Step 3:** Run the full gate `bash hooks/run-gate.sh` (foreground). Expected: GATE PASS.
- [ ] **Step 4: Commit** `feat: installer --with, drift reads enabledPlugins, sync warns on old names; v7 docs`.

## Release

This plan folds into the single v7.0.0 release task of the self-review-items plan.
- The user picks the optional plugins per machine. Approved: `cct-guards`, `cct-learning` and `cct-helpers` on both machines, not `cct-jev`, and language plugins only where used.
- The live update is attended.
