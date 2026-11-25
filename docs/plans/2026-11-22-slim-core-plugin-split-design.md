# Slim core: cct keeps the workflow, the rest becomes optional plugins — design

Status: approved by the user 2026-11-22 19:24 ("I agree to all what you proposed. go ahead!"). Part 2 of the "slim core" project (topic #1 of 2026-11-22). It ships after part 1, `2026-11-22-backlog-discipline-design.md`.

## 1. Intent

In the user's words: "skills/commend/sub-agents used in my sessions most of the time might not be used by others or in future sessions -> that means that most of these should be optional (plugin). Only the a core frame to run the defined workflow should remain."

**What "the defined workflow" means** (user, 18:48): "orchestrator = PO who does handle the input/backlog, delegates tasks to sub-agents, planned workload -> determine the size T1-T4 -> determines the team to do the work. This and everything related to that."

**Standing rule** (user, 2026-11-22): low use on our machines never justifies removing a part. Nothing is deleted; it becomes an optional plugin.

**Why:**
- A smaller, clearer default install with no habits of one user built in.
- Less cost per session: idle helpers and commands cost context, and idle checks cost time on every tool call.

## 2. Decisions taken with the user

- **The core is the workflow** (18:48), plus safety (my proposal, not objected to). Section 4 has the list.
- **The challenge command is part of T3/T4** (18:51):
  - it becomes a core step: the plan is challenged before coding at T3 and T4;
  - at T4 the architect runs it as part of its design review;
  - the orchestrator may start it itself, so `disable-model-invocation` goes;
  - the pre-merge checklist gets "plan challenged" for T3/T4.
- **The general coder is the default; language coders are optional** (18:52, "agreed" 18:54):
  - language know-how that matters moves into each variant's `PROJECT_CONTEXT.md`, for example the format check next to build and test;
  - `dotnet-coder`, `python-coder` and `rust-coder` move into the existing `plugins/dotnet-tools`, `plugins/python-tools` and `plugins/rust-tools`;
  - `java-coder` gets a new `plugins/java-tools` that holds only the agent;
  - templates name `cct:coder`, plus one line: "if the language plugin is installed, prefer its coder".
- **Packaging C: four optional plugins by purpose** (19:07). Section 5 has the list.
- **Two documents, two releases** (19:05): backlog discipline first, this second.

## 3. Goals, non-goals, anti-goals

- **Goals:**
  - `cct` holds only the workflow, safety and the plumbing they need;
  - every other part lives in an optional plugin in the same marketplace, installable alone;
  - templates and the user-level rules work with or without the optional plugins.
- **Non-goals:**
  - changing what any moved part does;
  - an open-brain backlog store (later, see part 1);
  - deleting anything.
- **Anti-goals:**
  - **A safety guard becoming opt-in.** A guard you forget to install fails silently.
  - **A rule or template that names a missing part as if it were there.** Every mention of an optional part reads "if installed".
  - **Shared helper copies drifting apart between plugins.**
  - **An update that silently drops what a machine has today**, with no word about it.

## 4. What stays in `cct` (the core)

- **Helpers:**
  - `coder`, `code-reviewer`, `tester` and `architect` (the T1-T4 teams);
  - `Explore` (the orchestrator's read discipline);
  - `ops` (the orchestrator never runs builds).
- **Commands:**
  - `sprint` (runs the backlog, grooming first after part 1);
  - `challenge` (T3/T4 step);
  - `sync-template` (how projects get updates).
- **Checks enforcing the workflow:**
  - `enforce-delegation` (orchestrator never codes);
  - `gate-before-merge`, `run-gate`, `pre-commit-test`, `no-push-main` and `git-pre-push`;
  - `enforce-agent-contract` (helper report rule);
  - `model-floor` (model defaults);
  - `backlog-item-check` (part 1);
  - `now-brief` (the backlog's Now and debt lines).
- **Safety checks:** `deny-secret-reads`, `deny-claude-md-writes` and `deny-hang-shapes`.
- **Plumbing:**
  - `dispatch` and `run-hook`;
  - `cct-session` (the session marker the project templates require);
  - `verify-hooks` (missing-script self-check);
  - `hooks/lib/`.
- **Report style:** `pm-report`, the orchestrator's voice to the stakeholder.
- **Templates:** all six variants and `setup-project.sh` / `.ps1`. The template-sync server stays where it is.

## 5. The optional plugins (packaging C)

All live in this repo's `dagonet` marketplace beside `cct` and the six MCP plugins. They are released together under the toolkit's one `VERSION`, and check 72 widens to every plugin manifest.

| Plugin | Holds | Why grouped |
|---|---|---|
| `cct-jev` | the `jev` skill with its Python and tests, `jev-route`, `jev-notice` | Sends spawn text to an outside service and needs a key: it must be its own choice. |
| `cct-learning` | the `retro-review` skill, `retro-ledger`, `retro-brief` | One loop: record helper failures, replay them, review them. |
| `cct-guards` | `read-size-gate`, `bash-output-guard`, `agent-budget-warn`, `post-edit-build` | Cost and context guards; each runs on many tool calls. |
| `cct-helpers` | the `commit`, `contribute-upstream`, `karpathy-guidelines` and `mcp-usage` skills | Small conveniences with no hooks. |

**The language plugins** (`dotnet-tools`, `python-tools`, `rust-tools`, and the new `java-tools`) gain their coder agents, per section 2. Their agent type names become `<plugin>:<lang>-coder`.

**Shared helpers.**
- **Self-contained plugins.** A plugin's hooks can only rely on files inside that plugin, so each plugin with hooks carries its own copy of the `hooks/lib/` files it uses and of `run-hook.sh`.
- **Pinned copies.** A new consistency check keeps each copy byte-identical to the `cct` original, the way the six templates are pinned today.
- **Hook classes.** Each optional plugin's hooks keep their current class and polarity (fail-closed or warn) unchanged.

**Jev's ties to the core.**
- **`model-floor` step-aside.** Today `model-floor.sh` steps aside when the clone's Jev switch is on. It keeps that step-aside and reads the same switch file. An absent plugin means the switch is never on, so the step-aside never fires.
- **Session marker.** `cct-session` keeps writing the session marker, which the step-aside also reads.

## 6. Rules and templates that name optional parts

- **`AGENT_TEAM.md`** (six variants, byte-identical):
  - the `retro-ledger` line reads "if `cct-learning` is installed";
  - the language-coder rows name `cct:coder` and "prefer the language plugin's coder if installed";
  - the challenge line becomes the T3/T4 step.
- **Variant `CLAUDE.md` team tables:** the `cct:<lang>-coder` rows become `cct:coder`, with the same note.
- **`enforce-delegation`:** its allowed and named helper types accept `cct:coder` and the plugin-namespaced coders (backlog #12).
- **`user-level-reference/CLAUDE.md`:**
  - the Read & Search section's `read-size-gate` sentence reads "if `cct-guards` is installed";
  - the karpathy line reads "if `cct-helpers` is installed".
- **`PROJECT_CONTEXT.md` and `project-instructions.md` (`mcp-usage`):** the same "if installed" form.
- **Agents mentioning `agent-budget-warn`:** the text says "if installed". Plugin agents carry no `hooks:` frontmatter (check 75), so no agent fails when the plugin is missing.

## 7. Moving machines over

- **Update order.** An update of `cct` alone removes the moved parts from that machine. To avoid surprise, the release notes come first and list one install line per optional plugin (`claude plugin install cct-guards@dagonet`, …), plus the language plugin for each language in use.
- **Delivery check.** `verify-user-level-drift.sh` gains an informational section listing which optional plugins are installed. It counts as drift only when the machine's own recorded choice says a plugin should be there.
- **The machine's choice is its `enabledPlugins`** (see section 10, item 3).
  - **Public default:** no optional plugin.
  - **This server and the PC:** user-approved 19:24: `cct-guards`, `cct-learning` and `cct-helpers` enabled on both; `cct-jev` not; a language plugin only where that language is in use. Jev stays off by default either way, per the model-ladder design.
- **Template sync** brings the template and `AGENT_TEAM.md` changes to each project as usual.

## 8. Tests

- **Plugin validation:** `claude plugin validate` on every plugin, in a temp HOME.
- **Install test.** In a temp HOME, install `cct` alone:
  - every core hook registers;
  - no moved script is referenced;
  - a project bootstrapped from each variant passes its first commit and PR with only `cct` (with part 1's backlog subsections in place).
- **Install everything** in a temp HOME: the hook set equals today's, so nothing is lost.
- **Consistency checks:**
  - pinned helper copies;
  - every plugin's `version` equals `VERSION`;
  - no file under a moved part remains in the `cct` root;
  - every template mention of an optional part carries "if installed".
- **Existing suites:** `scripts/test-hooks.sh` rows move with their hooks and run from the plugin path. The parser matrix covers every plugin's hooks.

## 9. Delivery

- **Release:** the release after part 1. It is a major bump (v7.0.0), because the helper type names change and a plain update removes parts.
- **Context Budget column** measured at release. The guards' move changes per-call cost, not context, so the release notes also give the hook count per tool call before and after.

## 10. Calls made after the builder check

1. **Language coders keep the floor and the report contract.** No silent loss.
   - **Today's gap:** `hooks/lib/agent-model.sh` (`am_resolve`) and `enforce-agent-contract.sh` ignore every non-`cct:` type.
   - **Fixed name table:** both gain a table of the four plugin coder types: `dotnet-tools:dotnet-coder`, `python-tools:python-coder`, `rust-tools:rust-coder` and `java-tools:java-coder`. The table gives each type's model and pipeline flag.
   - **Pinned:** a consistency check pins the table against those agent files' frontmatter.
   - **No sibling-plugin path lookup.**
2. **Jev step-aside without seeing cct-jev's files.**
   - **Own session marker:** `cct-jev` writes its own SessionStart marker. `model-floor` steps aside only when the clone's switch says `route: true` **and** this session has the `cct-jev` marker.
   - **Uninstalled plugin:** with `cct-jev` gone there is no marker, so the floor applies. This is fail-closed.
   - **Pinned copy:** `cct-jev` carries a copy of `agent-model.sh`, kept identical by the copy check.
3. **The machine's choice is `enabledPlugins`.** No new file.
   - **Drift:** the drift check lists the optional plugins as information, and counts drift only when `enabledPlugins` names a plugin that is not installed at `VERSION`.
   - **Installer:** the Linux installer gains `--with <plugin,...>` and installs nothing optional by default.
   - **Dev machines:** the set for this server and the PC is the user's call (section 7).
4. **`post-edit-build` and the `Post-edit build` field.**
   - **The field stays,** worded "used if `cct-guards` is installed".
   - **Moved sources** live under `plugins/<name>/`, for example `plugins/cct-guards/hooks/post-edit-build.sh`.
   - **This repo's own registration** in its root `.claude/settings.json` points at that path.
   - **The "nothing left behind" check** means: no moved script under the root `hooks/` or `skills/`.
   - **The format check is not a new field.** Each language variant's default `Test`/`Gate` suggestion in `setup-project.sh`/`.ps1` includes it (e.g. `dotnet format --verify-no-changes`).
5. **Base:** built after part 1 merges, on top of it.
6. **`hook-class.sh` is per plugin.** Each plugin's table lists only its own hooks, and is excluded from the identical-copy check, because it is data, not a helper. Check 74 runs per plugin.
7. **Renames are breaking, with a map.**
   - The v7.0.0 notes carry an old-to-new name table (`/cct:jev` → `/cct-jev:jev`, `cct:dotnet-coder` → `dotnet-tools:dotnet-coder`, …).
   - `sync-template` warns, and does not edit, when a kept project file still names an old one.

## 11. Left to the builder

- The exact file moves and the per-plugin `hooks/hooks.json`.
- Which `hooks/lib/` files each plugin needs.
- The name and format of the machine choice file.
- The order of moves within the branch.
