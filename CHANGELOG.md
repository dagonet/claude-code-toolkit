# Changelog

## 2026-07-19 — Downstream sync findings: hook-ref invariant, PROJECT-CUSTOM region, migration discipline (#43)

Response to `docs/2026-07-19-sync-template-dotnet-findings.md` (MMAgent's dotnet sync). Toolkit side: consistency §13 asserts every hook referenced by any variant's `settings.json` or agent frontmatter exists non-empty at the toolkit ROOT `hooks/` (root-tracked design — variants do NOT ship `hooks/`; now documented explicitly in `docs/template-sync.md` and `docs/architecture.md`). All 6 `CLAUDE.md` templates ship a `<!-- PROJECT-CUSTOM:BEGIN/END -->` sentinel region for project-owned extensions. `/sync-template` step 6b now materializes missing hook scripts via `template_apply_file(source="template")` (the server resolves root-tracked paths — never hand-copy), surfaces operating-model bumps when `CLAUDE.md`/`AGENT_TEAM.md` are in the change set, builds `applied_files` programmatically only, and re-runs `template_compute_status` after finalize as a corruption self-check. `CONTRIBUTING.md` now requires a CHANGELOG entry with a Downstream-migration subsection for behavior-changing PRs.

Server side (`mcp-dev-servers`): `template_finalize_sync` validates hash fields (`^[0-9a-f]{64}$`) and rejects path traversal; writes are LF-safe on Windows (`write_text(newline="")`); PROJECT-CUSTOM region awareness — when BOTH template and project carry the markers, region-only project edits reclassify to `UP_TO_DATE`, `apply_file(source="template")` splices the project's region into the applied template, and three-way merges exclude/reattach the region. Stored hashes remain full-content (no manifest migration).

### Downstream migration
- Re-run `/sync-template` once after updating: `CLAUDE.md` gains the PROJECT-CUSTOM sentinel — move any project-appended `CLAUDE.md` content INTO the region so future syncs preserve it mechanically.
- Update + restart the `template-sync-tools` server (`pip install -e` in its venv) before the next sync to get region preservation, hash validation, and LF-safe writes.
- No agent/hook behavior changes in this release.

## 2026-07-19 — Delegate-everything workflow (#42)

Operating-model shift: **the PO never does hands-on work at any tier** — coding, reviewing, testing, builds, env setup, and exploration are all sub-agent work on cheaper models (architect and code-reviewer stay opus). New `hooks/enforce-delegation.sh` (PreToolUse on `Edit|Write|NotebookEdit` + `Bash` in every variant) discriminates main-thread vs subagent via the `agent_id` stdin field: main-thread edits outside the orchestration surface (`docs/plans/`, `PROJECT_STATE.md`, `PROJECT_CONTEXT.md`, `.claude/`, `CLAUDE.md`, `AGENT_TEAM.md`) and main-thread build/test commands (incl. `hooks/run-gate.sh`) are denied with a delegate message; subagent calls always pass. Deliberately fail-open with a WARN-wrapper; kill-switch `.claude/delegation-off`.

Tier model: T1 = ONE coder via the uniform PR pipeline (a 3-line `Tier: T1` plan file satisfies the spawn gate; the PO direct-commit exception is deleted); T2 adds a code-reviewer (was T3+). New `ops` agent (sonnet) for env setup/downloads/binary ops/diagnostics/gate re-runs. `Explore` added to the roster (pass `model: "haiku"`/`"sonnet"`). Report agents carry a Team-mode reporting mandate (end with a SendMessage to `main`; bare idle = non-report) because the SubagentStop stop-gate does not fire on teammate idle. Stall runbook: never self-perform; dead-coder merge handoff via a fresh coder given the PR URL + branch + worktree.

PR: https://github.com/dagonet/claude-code-toolkit/pull/42

### Downstream migration
- Run `/sync-template`: pulls the new tier tables (`CLAUDE.md`, `AGENT_TEAM.md`), updated agents, and `settings.json` hook registrations.
- Step 6b materializes `hooks/enforce-delegation.sh` and registers it in the manifest; adopt the new `.claude/agents/ops.md`.
- Expect behavior changes: the PO can no longer edit source or run builds/tests (deny messages name the right agent); T1 fixes now spawn a coder; reviewers are spawned from T2 up.
- Escape hatch for emergencies: create `.claude/delegation-off` at the repo root.

## 2026-07-09 — Session-mining round 3: plan-mode friction, config hygiene (#40)

Mined two months of session transcripts plus a full config inventory. Root-caused the recurring plan-mode permission prompts: **plan mode overrides `permissions.allow` for tools it does not classify read-only**, so an allow-listed `mcp__plugin_context-mode_context-mode__*` never stopped the `ctx_*` prompts. Fix: new `hooks/allow-ctx-plan.sh` — a PreToolUse `permissionDecision: "allow"` hook (runs before the permission system) for the nine `ctx_*` tools, with a `PermissionRequest` fallback via `EVENT=permission-request`. Deliberately **not** 127-wrapped — an allow hook must fail open. It is a user-preference hook, documented in `settings-reference.md` and shipped in `hooks/`, but not registered in any template `settings.json`.

Also: `mcp__MCP_DOCKER__update_pull_request` added to all coder agents (the PO no longer edits PR bodies on their behalf); a "Read & Search Tool Selection" decision table in `user-level-reference/CLAUDE.md` replaces three previously contradictory search rules; `/sync-template` step 6b now registers manifest-untracked hook scripts via `template_apply_file(source="skip")` (never `"template"`, which would overwrite local edits), making hook drift visible to `template_compute_status` in consumers bootstrapped before hooks tracking. `verify-template-consistency.sh` gained an `update_pull_request` lock-in check.

Files touched: `hooks/allow-ctx-plan.sh` (new), `templates/*/.claude/agents/coder.md` + variant coders, `user-level-reference/{CLAUDE.md,settings-reference.md,agents/coder.md,skills/sync-template/SKILL.md}`, `scripts/verify-template-consistency.sh`.

PR: https://github.com/dagonet/claude-code-toolkit/pull/40

## 2026-07-09 — Session-mining round 2: SubagentStop stop-gate, fail-closed hooks (#39)

Added `hooks/enforce-agent-contract.sh` — a **SubagentStop stop-gate**: exit-2 blocks a coder from ending without `## Gate Results` + `## Spec Compliance` sections and a reviewer without findings or the literal `clean` (strict equality via a node parse of the last assistant message). A per-session+agent marker file bounds it to one forced continuation; a second non-compliant stop passes with a `CONTRACT-ENFORCER:` stderr signal to the PO. Deliberately fail-open when broken and **not** 127-wrapped (a missing stop-gate must not trap agents in an unstoppable loop).

Hardened the remaining enforcement layer: all PreToolUse script hooks in every variant now carry a 127-wrapper converting a missing script (fail-open by Claude Code design) into a loud `HOOK SCRIPT MISSING → exit 2`, because a synced project with an empty `hooks/` directory otherwise runs with its entire enforcement layer silently absent. `block-bash-vcs.sh` block messages now name the exact MCP replacement per subcommand. `/sync-template` gained a mandatory post-sync hook-script verification step. `verify-template-consistency.sh` repaired (a header rename had left it red on `main`) and extended with settings.json byte-identity checks.

Files touched: `hooks/enforce-agent-contract.sh` (new), `hooks/block-bash-vcs.sh`, `templates/*/.claude/{settings.json,agents/coder.md,agents/code-reviewer.md}`, `templates/*/AGENT_TEAM.md`, `templates/*/VERIFICATION_PLAYBOOK.md`, `scripts/verify-template-consistency.sh`.

PR: https://github.com/dagonet/claude-code-toolkit/pull/39

## 2026-07-09 — Merge gate + agent deliverable contracts (#38)

Weak-model-parity change set: move judgment into mechanism. Projects declare a gate via a `**Gate**:` field in `PROJECT_CONTEXT.md`; `hooks/run-gate.sh` runs it and writes `.gate/last-pass.json` `{sha,branch,ts,status}` on green; `hooks/gate-before-merge.sh` (PreToolUse on `mcp__MCP_DOCKER__merge_pull_request|mcp__github-tools__github_pr_auto_merge`) hard-blocks a merge without a fresh, SHA-matching artifact. Coder agents gained a `## Deliverable Contract` (grep-auditable `## Gate Results` + `## Spec Compliance` sections); `code-reviewer` is pinned to `opus` with an output contract (findings or the literal `clean`). A `VERIFICATION_PLAYBOOK.md` promotes the recurring incident rules to every template root.

Files touched: `hooks/{run-gate,gate-before-merge,pre-commit-test,no-push-main}.sh`, `templates/*/{PROJECT_CONTEXT.md,CLAUDE.md,AGENT_TEAM.md,VERIFICATION_PLAYBOOK.md,gitignore,.claude/settings.json,.claude/agents/*}`, `setup-project.{sh,ps1}`, `scripts/verify-template-consistency.sh`.

PR: https://github.com/dagonet/claude-code-toolkit/pull/38

## 2026-04-26 — Open Brain v0.3.0 sync

Synced template and reference docs to match Open Brain v0.3.0 (mcp-server@0.3.0, 14 tools): the existing `thoughts_*` and `system_status` tools are joined by a write-time wiki layer (`wiki_get`, `wiki_list`, `wiki_refresh`) and on-demand contradiction surfacing (`contradictions_list`, `contradictions_resolve`, `contradictions_audit`). Documents the per-repo opt-out env var `OPEN_BRAIN_TOOLS_DISABLED=wiki,contradictions`.

The session-bootstrap directive in `CLAUDE.md` keeps the unconditional `thoughts_search`/`thoughts_recent` mandate; the wiki-first rule is appended as an intentionally conditional follow-up for synthesis-style questions on a known topic, gated on the page being non-stale (`stale_since_n_thoughts > 5`, `open_contradictions_count > 0`, or `compiled_at` older than 7 days). The three-layer enforcement structure (`CLAUDE.md` bootstrap → MCP server instructions → `CLAUDE.local.md` hard requirement) is preserved — only extended.

Files touched: `templates/<6 variants>/CLAUDE.md`, `templates/<6 variants>/CLAUDE.local.md`, `user-level-reference/README.md`, `mcp-servers/HOWTO.md`, `docs/architecture.md`. `settings.json` and `settings-reference.md` already use the `mcp__open-brain__*` wildcard, so the new tools are permitted automatically.

Upstream: https://github.com/dagonet/open-brain/pull/7

Inspired-by: karpathy/442a6bf555914893e9891c11519de94f (gist) via Nate B Jones (youtu.be/dxq7WtWxi44)
