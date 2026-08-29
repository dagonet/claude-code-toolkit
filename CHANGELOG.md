# Changelog

## v2.2.0-pr15 — 2026-08-29

**Every hook assumed `node`, so on a box without it the whole enforcement layer was silently off.** Credit: the home-agent WSL dry-run report (2026-08-29) — a native Claude Code install ships no Node runtime, and `hooks/lib/git-cmd.sh` parsed the payload with `node -e … 2>/dev/null`. With node absent, `GC_TOOL`/`GC_CMD` came back empty and every gate fell through its `[ -n "$GC_CMD" ] || exit 0` guard: pushes to main, merges without a gate artifact, and commits without tests all passed, with nothing printed. 10 of the 12 hooks were affected.

**1. One shared JSON reader: `hooks/lib/json.sh`.** `json_get <json> <dotted.path>` tries `node`, then `python3` (`json.load(sys.stdin)`), then `jq`, and prints the scalar at that path or nothing. `hooks/lib/git-cmd.sh` sources it and reads `tool_name`, `cwd` and `tool_input.command` through it; `require-skills-block.sh` (`subagent_type`, `prompt`) and `enforce-agent-contract.sh` (`agent_type`, `transcript_path`, `agent_id`, `session_id`) do the same. `gc_protect_c_paths` — the quoted-`git -C <path with space>` protection that keeps the gates from evaluating the wrong repo — was a node regex substitution and is now pure `sed`, so the three git gates need no node-specific behaviour at all.

**2. Polarity, stated explicitly.** The three git gates (`no-push-main.sh`, `pre-commit-test.sh`, `gate-before-merge.sh`) **fail CLOSED** with none of the three parsers on PATH: `BLOCKED: no JSON parser (node, python3 or jq) on PATH — the git gates cannot inspect the command`, exit 2. The documented `<cwd>/.claude/git-guard-off` escape hatch still wins (looked for under the process cwd, since the payload cwd is unreadable then). The fail-open hooks stay fail-open and print exactly one stderr line instead of vanishing: `WARN: <hook>: no JSON parser on PATH — enforcement inactive`. Six of them (`read-size-gate`, `bash-output-guard`, `enforce-delegation`, `retro-ledger`, `retro-brief`, and `enforce-agent-contract`'s transcript scan) are embedded node *programs*, not field reads — they still require node specifically and say so: `WARN: <hook>: node not on PATH (found python3) — enforcement inactive`. Porting those to three backends is deliberately out of scope. Two more consequences worth knowing: on a node-less box the WARN fires per invocation (`read-size-gate` on every `Read`), and `require-skills-block.sh`/`enforce-agent-contract.sh` disable themselves silently if `hooks/lib/json.sh` is missing — they were fail-open by construction, unlike the git gates, which block on the same condition. `agent-budget-warn.sh` never used a parser (it greps the raw payload) and is untouched.

**3. `**Protected branches**:` — an optional PROJECT_CONTEXT.md field (G3).** `no-push-main.sh` and `gate-before-merge.sh` hardcoded `main|master`. They now read the field with the same tolerant grep as `**Gate**:` (leading list marker, backticks, comma- or space-separated names). Absent → `main master` as before; `- **Protected branches**: develop release` → those two instead; `none` (or an empty value) → nothing is branch-protected, though `gh pr merge` stays gated because it is a merge whatever branch it runs on. `gc_targets_main_ref` takes the repo as a second argument so the ref check uses the same list. PR16 adds the field line to the PROJECT_CONTEXT templates.

**4. `.env` deny precision (BUG 6).** `Read(.env*)` also denied `.env.example`, a tracked file most repos ship as the documented variable list. All six `templates/*/.claude/settings.json` and `user-level-reference/settings.json` now enumerate `Read(.env)`, `Read(.env.local)`, `Read(.env.*.local)`, `Read(.env.production)`, `Read(.env.staging)`, `Read(.env.development)`. A new consistency check asserts the six names AND that the `.env*` glob has not come back.

**Fixtures.** The no-parser cases run each hook with `PATH` pointing at a directory of one-line `exec` wrapper scripts for git and coreutils only — text files, so nothing is copied and Windows DLL loading is not involved — and the suite asserts *first* that `command -v node|python3|jq` genuinely fails inside that PATH, since a fixture that still sees node would pass green and prove nothing. The git-gate must-block/must-not-block cases (including the quoted `-C` with a space) are then repeated on a python3-only and on a jq-only PATH.

### Downstream migration

1. **Re-copy the hooks INCLUDING `lib/`**: `cp -r user-level-reference/hooks/. ~/.claude/hooks/`. The new `hooks/lib/json.sh` is required — `git-cmd.sh` refuses to run without it (`BLOCKED: … hooks/lib/json.sh missing`), by design: a missing reader must not silently disarm the gates. In a consumer project `/sync-template` picks up `hooks/**` including `hooks/lib/`.
2. **Check your PATH.** If the box has none of `node`, `python3`, `jq`, the git gates now block instead of waving everything through. Install one — `jq` is the smallest, `node` unlocks the five node-only hooks.
3. **User-level `settings.json` deny list changed**: replace `Read(.env*)` with the six enumerated names, or `.env.example` stays unreadable.
4. **Optional**: add `- **Protected branches**: <names>` to `PROJECT_CONTEXT.md` if your trunk is not `main`/`master`. Omitting it keeps the old behaviour exactly.

12 hook scripts (2 lib files), 8 skills; 212 → 227 consistency assertions and 204 → 243 hook fixtures.

## v2.1.5 — 2026-08-29

**Two consumers hit the same wall from opposite sides: the gate artifact never matched what agents actually commit, and the delegation guard denied the PO's own sync commit.** Credit: Yutraffic-Challenge (PR #223, commits e59e6fd vs 567f0d1) and panoscribe (PR #123).

**1. `hooks/run-gate.sh` keys the artifact on the WORKING TREE.** The PreToolUse hook fires *before* a chained `git add … && git commit` stages anything, so v2.1.3's index tree was the PARENT tree, and v2.1.3-round-2's `git diff --quiet` guard recorded no tree at all whenever the working tree was dirty — which is the ordinary agent shape. The artifact therefore matched nothing and the single-run merge path never fired in practice. The guard is replaced with a temp-index hash: a copy of the real index is `add -A`'d under `GIT_INDEX_FILE` and `write-tree`'d, so `tree` is always recorded, the real index is never touched, and `.gitignore` is respected (`.gate/` and build output stay out of the hash). Consequently `git add -A && git commit`, `git commit -a`, and separate add/commit calls all yield `HEAD^{tree} == tree`. A PARTIAL-add commit mismatches **by design** — the committed tree is not what was gated, so `gate-before-merge.sh` correctly demands a fresh run. `gate-before-merge.sh` itself is unchanged apart from its header, which now states the sha-OR-tree acceptance and what `tree` means as of v2.1.5.

**Caveat, stated in the hook header too:** the hash is taken *before* the gate command runs — deliberately, so a failing gate cannot bless its own mutations. A gate that MUTATES the tree therefore makes the following commit mismatch anyway: a formatter inside the gate rewriting tracked files, or gate-generated output that is untracked and not gitignored (coverage reports, `pytest-of-*`, build logs). `add -A` on the temp index writes blobs for every unignored untracked file on every run, so such output lands in the *next* run's hash and never in this one's. The fix is on the project side: gitignore everything the gate produces, and run the formatter before the gate rather than inside it. Mirrored byte-identical to `user-level-reference/hooks/run-gate.sh`. The toolkit's own `.gitignore` gained `/.gate/`, which the tree key makes load-bearing (every `templates/*/gitignore` already had it).

**2. `hooks/enforce-delegation.sh` exempts git/gh segments.** The Bash deny matched the whole command STRING, so `git add hooks/run-gate.sh` was denied by the `hooks/run-gate.sh` pattern and a commit message naming a test runner could trip the runner patterns — blocking the very sync commit the `sync-template` skill prescribes. The command is now split on `&&`, `||`, `;`, `&`, `|`, and newline; each segment is stripped of a leading `cd X` and of `VAR=value` assignments; a segment whose first token is `git` or `gh` PASSES (git/GitHub I/O is the PO's documented role, per `AGENT_TEAM.md`); every other segment keeps the existing deny logic verbatim. `git add x && bash hooks/run-gate.sh` still denies on its second segment, and the `VAR=value` strip closes a pre-existing hole (`CI=1 pytest` used to pass). Project-only hook — there is deliberately no `user-level-reference` copy.

**3. `sync-template` skill.** Step 9 now spells out the full sync-commit sequence under v2.1.3+ hooks: `git add -- <paths>` → `git commit` (with `**Test**` present this runs tests only and writes no artifact) → delegate ONE `bash hooks/run-gate.sh` run to `ops` **after** the commit → `git push -u` → `gh pr create` → `gh pr merge --squash --delete-branch` → `git fetch -p`. Gating before the commit yields "artifact stale" at merge time unless the tree is identical. Steps 3 and 8 gained a **positive control** for gate liveness — a temp script piping a `git push origin main` payload into `hooks/no-push-main.sh`, run via `bash <path>`, expecting exit 2 + `BLOCKED`; exit 0 means the gates are inert, with the recovery note. (`Bash(true)` succeeding proves only that nothing blocked it; an inert layer passes that test too.) Step 9's context-mode check is now `grep -c '^# context-mode' CLAUDE.md` must be `0` — the template's own sentinel section contains the substring by design, so a substring grep false-positives on a clean file.

**4. `AGENT_TEAM.md` + the 11 coder contracts.** The merge protocol notes that CI fires on `pull_request` and push-to-main, so a bare branch push produces no run — open the PR first, then look up the run id; an empty workflow list right after `git push` is not a CI failure. The working-tree gate-key sentence is added to the merge protocol and to all 11 coder files' deliverable contract.

### Downstream migration

1. Re-copy `hooks/run-gate.sh`: `cp -r user-level-reference/hooks/. ~/.claude/hooks/` (the standard hooks re-copy). In a consumer project, `/sync-template` picks up both `hooks/run-gate.sh` and `hooks/enforce-delegation.sh` (project-only — it has no user-level mirror).
2. Re-copy the sync skill: `cp -r user-level-reference/skills/sync-template ~/.claude/skills/`.
3. **Gitignore `.gate/` and everything your gate generates**, or the commit tree will not match the gated tree. `add -A` on the temp index writes blobs for every unignored untracked file on every run, so an un-ignored `.gate/`, coverage report, `pytest-of-*` directory, or build log silently pushes the next run's hash off the tree you commit. Also move any formatter out of the gate command and run it beforehand — the hash is taken before the gate runs, so a gate that rewrites tracked files mismatches by construction.
4. Nothing else changed — no settings.json delta, no new files.

12 hook scripts, 8 skills; 212 consistency assertions (unchanged) and 184 → 204 hook fixtures.

## v2.1.4 — 2026-08-29

Follow-ups from penumbra's third sync report (cf15dcc → 4dfd894, otherwise clean) plus two deferred review minors. **Wording correction:** the v2.1.3 entry's "`pre-commit-test.sh` now prefers `run-gate.sh`" sentence read as if the second gate run were eliminated; it is not, in the common case — see the amendment inline above. **Sync skill:** the step 3 smoke-test paragraph now warns that a hook probe must live in a script file run via `bash <path>`, never inline — a compound command that merely mentions a guarded git command (e.g. `git push origin main`) trips the gate it is trying to test, and the result is then uninterpretable. Step 9's commit guidance drops `git add -A excluding CLAUDE.local.md` for staging exactly the sync's touched files (the step-7 `applied_files` results plus any step-6 `git rm` deletions) via `git add -- <paths>` — `-A` sweeps up untracked run artifacts that were never part of the sync. **Retro ledger:** `hooks/retro-ledger.sh` (+ `user-level-reference/hooks/retro-ledger.sh` mirror, newly added) now tallies a `hooks/agent-budget-warn.sh` block separately as `budget=<n>` instead of folding it into `blocks=[...]` — a budget ceiling is a liveness control tripping as designed, not a failure needing investigation. A resumed subagent keeps its prior tool-call counter, so a budget block soon after a resume may just reflect the PO's own choice to keep going. `hooks/retro-brief.sh` is unchanged — it prints ledger lines verbatim. **Two deferred review minors:** `hooks/pre-commit-test.sh`'s placeholder-`{{...}}` guard at the tail of the script was dead code (both `TEST_CMD` and `GATE_CMD_RAW` are already stripped of a `{{...}}` placeholder at extraction, and an empty `TEST_CMD` exits earlier) — removed, with a one-line comment explaining why; and `scripts/verify-template-consistency.sh` check 13's hook-name extraction regex widened from `[a-z-]*` to `[A-Za-z0-9_-]*` (check 24's census does not share this class, so it is untouched). A new check 26 asserts that all six `templates/*/CLAUDE.md` carry the `context-mode` sentinel on the line immediately above `PROJECT-CUSTOM:BEGIN`. 210 → 212 consistency assertions, 182 → 184 hook fixtures.

### Downstream migration

1. Re-copy the sync skill: `cp -r user-level-reference/skills/sync-template ~/.claude/skills/` — the corrected smoke-test and step-9 staging guidance only helps on the next sync.
2. Re-copy `hooks/retro-ledger.sh`: `cp -r user-level-reference/hooks/. ~/.claude/hooks/` (the standard hooks re-copy step) picks up both the `budget=<n>` field and the newly-added user-level mirror.
3. Nothing else changed — no new files, no settings.json delta, no agent-file delta.

## v2.1.3 — 2026-08-29

**A fifth consumer's report (penumbra) caught stale text the v2.0 native-git move left behind, and a sixth (panoscribe) caught two ways the sync's own final step could silently corrupt or block itself.** The architect agent's `Rules` section still instructed itself to "Use MCP GitHub tools for issue comments" and "Use MCP git tools for git operations" — tools it does not carry in its `tools:` frontmatter and that no longer exist in this repo's MCP surface. `AGENT_TEAM.md` already documents the real contract ("Git runs through the git/gh CLI"; "agents without Bash return work; the PO commits"), so the architect's own rules contradicted the team doc it is supposed to follow. Both stale lines are replaced with one bullet: "No git or GitHub tools — return your deliverable (ADR/doc/plan text) to the PO, who commits it with the git CLI." Applied to `templates/*/.claude/agents/architect.md` (all six variants) and `user-level-reference/agents/architect.md`.

**Correction (fix round 1):** `architect.md` is NOT byte-identical across variants — dotnet, dotnet-maui, and rust-tauri each carry a real per-variant "Architecture Knowledge" section (Clean Architecture layers, Tauri IPC boundary, etc.), and the first pass's `cp` from `templates/general/` silently deleted them. Worse, java and python had been seeded from the dotnet file at some earlier point and carried a wrong "You are a senior software architect with .NET conventions awareness" line plus a Clean-Architecture-via-Microsoft.Extensions.DependencyInjection knowledge section that named the wrong stack entirely. All six variant files are now restored from `cf15dcc` (pre-fix) with only the two-bullet → one-bullet edit applied on top; java and python additionally got their `.NET conventions awareness` line and knowledge section rewritten to their own stack (Spring Boot layered architecture for java: Controller → Service → Repository; Route/View → Service → Repository/ORM for python). There is no byte-identity assertion for `architect.md` in `verify-template-consistency.sh` — only `AGENT_TEAM.md`, `settings.json`, and `ops.md` carry that check — so this was a content-review gap, not a broken invariant.

Separately, panoscribe's sync hit two failures at the commit step itself. First, delegating the final commit to a worktree-isolated agent (`coder`, `*-coder`, `tester`, `test-writer` all set `isolation: worktree`) creates that worktree from `main`, whose `hooks/` predate the sync it's supposed to commit, while the session's hot-reloaded `settings.json` already fires the *new* gates — every Bash call in that worktree then blocks, even `ls`. Second, the context-mode plugin re-appends its `# context-mode — MANDATORY routing rules` block to `CLAUDE.md` after `PROJECT-CUSTOM:END` on every session start, so a `CLAUDE.md` the sync cleaned earlier in the session is dirty again by commit time. `user-level-reference/skills/sync-template/SKILL.md` gained step 9 ("Commit the Sync"): the PO commits the synced tree directly from the main thread (never a worktree-isolated agent), and checks `git diff CLAUDE.md` for a re-appended context-mode block before staging. Panoscribe also flagged a stale piece of migration advice: the v2.1.1 CHANGELOG entry told consumers to restart the session before any git operation because the gates were inert until then, but v2.1.2 §1 made hooks hot-reload immediately — the two entries contradicted each other. The v2.1.1 entry is amended in place to note the supersession.

Yutraffic-Challenge re-synced to confirm v2.1.1/v2.1.2 hold (apply order, hot-reloaded `${CLAUDE_PROJECT_DIR:-.}` paths, region markers, a clean manifest drop) and flagged a latency gap: `hooks/pre-commit-test.sh` re-derives and re-evals the Test/Gate command from `PROJECT_CONTEXT.md` on every commit, duplicating work `hooks/run-gate.sh` already does — and a green commit gate leaves nothing behind for `gate-before-merge.sh` to check at merge time, forcing a second ~2-minute gate run there. `pre-commit-test.sh` now prefers `run-gate.sh` over evaluating the Gate command itself when it sits alongside the hook, **when there is no `**Test**` field** (see the precedence correction below). **This does not eliminate the second gate run in the common case.** Five of the six templates ship a `**Test**` field, and when it is present `pre-commit-test.sh` runs that command only and writes no `.gate/last-pass.json` artifact — `gate-before-merge.sh` still needs its own `bash hooks/run-gate.sh` before the first merge of a branch. What the tree-keyed artifact (fix round 1, below) actually buys: run `run-gate.sh` once before that first merge, and its recorded tree hash spares a re-run on a later tree-identical commit on the same branch (an amend-message, a docs-only re-commit) — and, separately, lets a Gate-only repo's own commit-time `run-gate.sh` invocation count toward the merge gate instead of running twice.

### Fix round 1 (same-day review)

A review of the first pass found two Critical issues plus the architect.md content-loss regression corrected above. All fixed on the same branch before merge:

- **Placeholder Gate guard.** A still-unfilled `**Gate**: {{GATE_COMMAND}}` could route straight into `run-gate.sh` (which itself no-ops on a placeholder and returns 0) producing a false green with nothing ever run. `hooks/pre-commit-test.sh` now strips a placeholder Gate command to empty before deciding whether to invoke `run-gate.sh` or fall through to the WARN ("nothing to run") path — matching the placeholder guard that already existed for a directly-eval'd `**Test**`/legacy-Gate command.
- **Precedence ruling.** `**Test**` wins when present — the cheap commit path is unchanged for repos that declare a lightweight Test command. `run-gate.sh` is consulted ONLY when there is no Test field and a real (non-placeholder) Gate line exists. A repo that wants the full gate at commit time removes its Test line. (This reverses the first pass's "Gate wins when both present," which the review correctly flagged as an undocumented behavior change nobody asked for.)
- **Tree-keyed gate artifact (Critical 2, and closes penumbra's earlier #2c report).** `hooks/run-gate.sh` now writes both `sha` (HEAD) and `tree` (`git write-tree`, the INDEX tree) into `.gate/last-pass.json`. At PreToolUse commit time — `pre-commit-test.sh` invoking `run-gate.sh` before the `git commit` actually runs — the artifact's `sha` is still the PARENT commit, but its `tree` is exactly the tree the new commit is about to get. `hooks/gate-before-merge.sh` now accepts the artifact when EITHER the sha matches HEAD OR the tree matches `HEAD^{tree}`, still within the 60-minute freshness window. Accepted miss, documented inline: `git commit -a` or an extra `git add` after the gate ran stages more than the snapshot that was hashed, producing a tree mismatch too — the merge gate then falls back to requiring a fresh run, same as before this fix. A full chain fixture (stage → pre-commit-test.sh allows → real `git commit` → `gate-before-merge.sh` accepts; and the negative: a further commit → stale/blocked) is now in `scripts/test-hooks.sh`.
- **Recursion guard.** A `**Gate**` command that itself invokes `bash hooks/run-gate.sh` (copy/paste mistake, or a gate that shells out to a wrapper that shells out here) would recurse until the process/fd limit killed it. `run-gate.sh` exports `RUN_GATE_ACTIVE=1` before running the gate command and refuses to proceed (`BLOCKED: **Gate** must not invoke run-gate.sh itself`, exit 2) if it finds that variable already set on entry.
- **`scripts/verify-user-level-drift.sh`** now `cd`s to the repo root first (works from any cwd) and compares `hooks/**`, `skills/**`, and `agents/**` against `~/.claude`, not just `CLAUDE.md`; it ends with `N files checked, M in sync, K drift` and exits 1 only when `K > 0`.
- **Sync skill clarifications, all from consumer reports:** the skill is `disable-model-invocation: true`, so "run `/sync-template`" in a migration note means the human types it — a PO session or a scheduled routine cannot invoke it; a harmless `Bash(true)` runs right after the `settings.json` write as a smoke test, and a block there means the recovery note applies; `git rm`/`git add`/`git commit` during a sync are the PO's documented git-I/O role per `AGENT_TEAM.md`, not hands-on coding.
- **`templates/*/CLAUDE.md` context-mode sentinel — corrected placement (fix round 2).** The first pass put the literal substring `context-mode` on the inner placeholder comment INSIDE the PROJECT-CUSTOM region. That does not work: the sync server's region split keeps the whole BEGIN..END block from the project side once a project has customized it (BEGIN line included), so the sentinel would never reach an already-synced consumer — only a brand-new project. It is now a template-owned line immediately ABOVE `PROJECT-CUSTOM:BEGIN`: `<!-- Project-specific rules and plugin routing blocks (context-mode, …) belong inside the PROJECT-CUSTOM region below -->`. The BEGIN/END marker lines are byte-for-byte unchanged (the consistency check's `PROJECT-CUSTOM:BEGIN` prefix grep and `tail -n 1` END check both still pass), and the inner placeholder comment reverts to its original text since it no longer needs to carry the sentinel — credit penumbra.
- 173 hook fixtures (up from 165), 210 consistency assertions.

### Fix round 2 (re-review)

- **Placeholder `**Test**` + real `**Gate**` was still a silent false green.** dotnet and dotnet-maui ship `PROJECT_CONTEXT.md` with exactly this shape (`**Test**: {{TEST_COMMAND}}` alongside a real `**Gate**:`) — round 1's placeholder guard only covered the Gate side. `hooks/pre-commit-test.sh` now strips a `{{...}}` `TEST_CMD` to `""` immediately after extraction, so precedence correctly falls through to the real Gate / `run-gate.sh`; if both fields are still placeholders, it falls all the way to the WARN path — never a silent exit 0.
- **`RUN_GATE` resolution was cwd-fragile.** `"$(dirname "$0")/run-gate.sh"` is a relative path when the harness invokes `bash hooks/pre-commit-test.sh`; it was not re-resolved until first USED, by which point the script had already `cd`'d into `REPO_PATH` — which `git -C <other-repo> commit` can point anywhere. The stale relative path would then resolve against the wrong repo: silently missing there (masking an intended `run-gate.sh` as the legacy eval path) or, worse, executing that other repo's own `hooks/run-gate.sh`. `RUN_GATE` is now absolutized (`$(cd "$(dirname "$0")" && pwd)/run-gate.sh`) at the top of the script, before any `cd`.
- **User-level `run-gate.sh` mirror.** The stale comment in `scripts/verify-template-consistency.sh` (check 21) claiming "most root hooks... deliberately do not [mirror]" is corrected — `run-gate.sh` IS mirrored as of the previous round, because the user-level `pre-commit-test.sh` shells into it. If a machine's `~/.claude/hooks/run-gate.sh` predates that (never migrated), the user-level `pre-commit-test.sh` now WARNs and falls back to eval'ing the Gate command directly instead of a silent no-op or a 127.
- **`run-gate.sh` tree recording is now conditional.** `git write-tree` hashes the INDEX; if the working tree has unstaged changes beyond it, a later `git commit -a` (or an extra `git add`) would fold those in too, producing a tree different from the one just hashed. `run-gate.sh` now only records `tree` when `git diff --quiet` confirms the working tree matches the index; otherwise `tree` is `""` and only the sha match applies at merge time. Documented in `run-gate.sh`'s header comment and in `user-level-reference/settings-reference.md`.
- **Test-path repos write no gate artifact at commit.** Five of the six templates ship a `**Test**` line (only dotnet-maui is Gate-only out of the box), so the single-run `pre-commit-test.sh` → `run-gate.sh` win from the previous round applies to Gate-only repos; a Test-path commit runs the lightweight Test command directly and leaves `.gate/last-pass.json` untouched — `gate-before-merge.sh` still needs a separate `bash hooks/run-gate.sh` before merging those. Fixture added asserting no artifact appears after a Test-path commit.
- Malformed bold fixed in the "Precedence ruling" bullet above (stray trailing `**` inside a backtick span).
- Root `CLAUDE.md`'s Gate/drift sentence now names the widened `hooks/**`/`skills/**`/`agents/**` comparison instead of just `CLAUDE.md`.

### Downstream migration

1. Type `/sync-template` yourself (the skill is `disable-model-invocation`; a PO session or a scheduled routine cannot invoke it) to pick up the edit to `.claude/agents/architect.md` as an AUTO_UPDATE, unless your project has locally edited that file — in which case it shows as CONFLICT and any project-specific customizations should live inside the file's PROJECT-CUSTOM region, not mixed into the template body.
2. User-level: re-copy `user-level-reference/agents/architect.md` to `~/.claude/agents/architect.md`.
3. Re-copy the sync skill: `cp -r user-level-reference/skills/sync-template ~/.claude/skills/` — the new commit step (main-thread only, context-mode block check) only helps on the next sync.
4. If the CHANGELOG describes skill behaviour you don't see, re-read `SKILL.md` from disk — the skill text is injected at invocation from whatever is on disk at that instant.
5. Re-run `bash scripts/verify-user-level-drift.sh` from anywhere in the repo (it now `cd`s to root itself) to see the widened `hooks/`/`skills/`/`agents/` comparison against `~/.claude/`. If it reports `run-gate.sh` missing at user level, `cp -r user-level-reference/hooks/. ~/.claude/hooks/` (the standard hooks re-copy step from earlier releases) already covers it — no separate step needed, just re-run it.
6. `CLAUDE.md`'s new sentinel line arrives with the next `CLAUDE.md` sync as ordinary template text — accept it. It lives immediately ABOVE the `PROJECT-CUSTOM:BEGIN` marker, a template-owned line the sync server keeps; it does not touch the marker lines or the region your custom content lives between.

## v2.1.2 — 2026-08-29

**A fourth consumer synced and hit three failures that all trace to the same blind spot: the sync knows *what* to write but not *when*, and the hooks it writes assume a cwd nobody guarantees.** Built from the **Motorsport-Manager-AI-Agent** report (dotnet variant, `59ec37c` → `5c64a9b`). As with v2.1.1, nothing here is a feature.

### 1. The sync had no apply order, and `settings.json` takes effect immediately

Hooks hot-reload: the moment `.claude/settings.json` lands on disk, the running session is using it. Applying it before the v2 hook scripts therefore wired the **new** `Bash|PowerShell` matcher to the **old** `gate-before-merge.sh`, which could not parse a command payload it had never seen — so it exited non-zero on everything. The consumer spent the rest of that session fail-closed on `ls`.

`user-level-reference/skills/sync-template/SKILL.md` step 3 now carries a numbered apply order — `hooks/lib/**`, then `hooks/*.sh`, then `.claude/agents/*`, `.claude/rules/*`, `.claude/settings.json`, everything else — with the reason stated inline, and the note that the same order binds the CONFLICT (step 4) and new-file (step 5) paths. Step 6's `TEMPLATE_DELETED` branch gained the matching constraint: a template-removed hook is deleted only *after* the new `settings.json` is applied **and** the 6b reference grep re-run against it shows the hook unreferenced — deleting it while the in-memory settings still name it turns every matching call into a 127 fail-close. And there is now a recovery note for the state the consumer was actually in: if every Bash call is blocked mid-sync, apply `hooks/lib/git-cmd.sh` and the three gates through `template_apply_file` (which needs no shell) — do **not** restart first, the half-applied state persists on disk.

### 2. Hook commands resolved against the shell's cwd

`bash hooks/x.sh` is relative. A `cd` inside any earlier Bash call persists for the session, so from that point on every hook exited 127 and the 127-wrapper announced `HOOK SCRIPT MISSING` — for a file sitting right where it belongs — and advised a full re-sync that would not have helped.

Command hooks are given `CLAUDE_PROJECT_DIR`, and `"$CLAUDE_PROJECT_DIR"/path/script.sh` is the documented placeholder form. Every hook `command:` in all six `templates/*/.claude/settings.json` and in the 11 coder-agent frontmatter blocks now reads `bash "${CLAUDE_PROJECT_DIR:-.}/hooks/<name>.sh"` — written with the `:-.` default so a host that does not export the variable degrades to the old cwd-relative behaviour instead of hard-blocking every tool call on a 127. The 127 wrapper stays (it is the only thing that turns a fail-open into a fail-close) but its message now names the absolute form and says "check that `hooks/` exists at the project root" instead of recommending `/sync-template`. Verified in Git Bash from an unrelated cwd with both a backslash and a forward-slash `CLAUDE_PROJECT_DIR`: `rc=0` either way, where the relative form is a 127.

`scripts/verify-template-consistency.sh` gained check 24, which fails if any hook `command:` still uses the cwd-relative form and fails if none uses the `${CLAUDE_PROJECT_DIR:-.}` form (so a broken extraction cannot pass vacuously). The check-13 hook-ref extraction was re-anchored on the `command:` line and now accepts both forms — that also keeps the `Bash(bash hooks/run-gate.sh*)` **permissions** pattern, which is a prompt rule and not a hook, correctly out of the set. Skill step 6b matches both forms for the same reason.

### 3. `accept-template` deleted hard-won lines from agent definitions

Only `CLAUDE.md` carried `PROJECT-CUSTOM` markers, so a mature downstream's accumulated agent instructions had nowhere safe to live. The server's region split is file-agnostic — shipping the markers *is* the whole fix. All 59 files under `templates/*/.claude/agents/*.md` (including `Explore.md`) and all six `AGENT_TEAM.md` now end with the same marker pair `CLAUDE.md` uses. New check 25 asserts every one of those 65 files ends with it. The skill notes that these files now merge like `CLAUDE.md`, that existing custom lines must be moved into the region once, and — closing a gap the markers would otherwise open — that "empty region" in the accept-template disqualifier means *no content beyond the shipped placeholder comment*, so the safety net keeps firing.

User-level files (`user-level-reference/agents/*.md`) are deliberately **not** marked: nothing syncs them. No check compares template and user-level agents byte-for-byte, so nothing needed adjusting there.

### Downstream migration

1. **Re-copy the sync skill**: `cp -r user-level-reference/skills/sync-template ~/.claude/skills/` — the apply order and the deletion ordering live there, and they only help before the next sync starts.
2. **Re-sync each consumer project** to pick up the `PROJECT-CUSTOM` regions and the `$CLAUDE_PROJECT_DIR` hook paths. `settings.json` and the agent files will both show as CONFLICT in a project that edited them; resolve with the region splice rather than accept-template.
3. **Move existing custom agent lines into the region.** On the first sync that brings the markers in, anything a project added to `.claude/agents/*.md` or `AGENT_TEAM.md` is still *above* the BEGIN marker, i.e. still template territory. Cut it into the region once; after that it survives.
4. **If your `settings.json` is locally modified** and you keep it: replace each `bash hooks/<name>.sh` in a `"command"` value with `bash "${CLAUDE_PROJECT_DIR:-.}/hooks/<name>.sh"` by hand. Leave the `Bash(bash hooks/run-gate.sh*)` entry in `permissions.allow` alone — it is a prompt pattern, not a hook.

## v2.1.1 — 2026-08-29

**Three consumers synced v2.0 → v2.1 and all three found the same shape of bug: a mechanism that reported success while doing nothing.** This is a patch release built entirely from their reports — **panoscribe** (python variant, `59ec37c` → `d7251b9`), **penumbra** (python, → `d7251b9`, write-up in that repo at `docs/reviews/2026-08-29-sync-template-feedback.md`), and **Yutraffic-Challenge** (rust-tauri, [PR #221](https://github.com/dagonet/Yutraffic-Challenge/pull/221)). Nothing here is a new feature; every change closes a path where enforcement was silently off.

### The three HIGH items

**1. The git gates could run with everything disabled, and said nothing.** Two independent paths, both ending in `exit 0`. (a) `hooks/lib/git-cmd.sh` was never materialised — the sync's hook-verification step greps for `bash hooks/<name>.sh` and never saw the *sourced* lib. Bash returns non-zero from a failed `.` but keeps going, so every `gc_*` helper was undefined, `GC_CMD` stayed empty, and `[ -n "$GC_CMD" ] || exit 0` waved through every push, commit and merge. (b) The sync rewrites the three gate scripts to their v2 (command-parsing) form while the *running* session still holds the pre-v2 `settings.json`, which invokes them on `mcp__git-tools__git_push` / `git_commit`. Those payloads carry no `tool_input.command`, so the v2 gates again found nothing and allowed everything — for the rest of that session.

Both now **fail closed**. Each gate checks its lib exists before sourcing it and exits 2 with `run /sync-template step 6b`; `no-push-main.sh` and `pre-commit-test.sh` exit 2 on a `mcp__git-tools__git_(push|commit)` tool name with `settings.json predates this hook (MCP matcher) — restart the session after /sync-template`. `gate-before-merge.sh` keeps its existing MCP branch (the GitHub merge tools are gated unconditionally); `mcp__git-tools__git_merge` never existed in any shipped matcher, so nothing was added for it. The `sync-template` skill's final report now leads with the restart warning.

**2. The native-git move left an MCP bypass open.** v2.0 dropped the `mcp__git-tools__git_commit|git_push` PreToolUse matchers because git runs through the CLI now. But `git-tools` is registered at **user** level (`~/.claude.json`), so it stays reachable in every project, and under `"defaultMode": "auto"` an `mcp__git-tools__git_push` to `main` ran with no hook on it at all. Seven write ops — `git_push`, `git_commit`, `git_revert`, `git_merge`, `git_rebase`, `git_reset`, `git_push_tags` — are now in `permissions.deny` in all six variants and in `user-level-reference/settings.json`; `mcp__git-tools__*` stays in `allow` for the read ops. Five of the seven (`git_push`, `git_commit`, `git_revert`, `git_rebase`, `git_reset`) exist in today's server — `git_revert` creates a commit and bypassed `pre-commit-test.sh` exactly as `git_commit` did. `git_merge` and `git_push_tags` are denied pre-emptively and are harmless no-ops.

**3. A project's own agents lost their hook wiring on every sync.** Both `SubagentStop` matchers enumerated the template's coder names, so a project that added `cpp-coder` had `^(coder|code-reviewer|tester|architect)$` written back over `^(coder|cpp-coder|…)$` with no warning — the agent files survived, the wiring did not. The matchers now own the *shape*: `^([a-z0-9]+-)?coder$|^code-reviewer$|^tester$|^architect$`. `hooks/require-skills-block.sh` binds `coder|*-coder` for the same reason, and the `AGENT_TEAM.md` binding-table row says so.

### Also

- `hooks/pre-commit-test.sh` falls back to **Gate** when `PROJECT_CONTEXT.md` declares no **Test** command (projects that gate rather than test made it a silent no-op), and prints `WARN: pre-commit-test: no Test/Gate command in PROJECT_CONTEXT.md — nothing verified` when it has neither. A silent pass was indistinguishable from a green run. **Latency note:** a Gate-only project now runs its whole gate — build, tests, format, lint — on every `git commit`, which is slower than the test run this hook used to imply. Add a `**Test**:` line to `PROJECT_CONTEXT.md` to get the cheap path back; the escape hatch (`.claude/git-guard-off`) still works. The block message also names the command that failed and carries the last 20 lines of its output, instead of "Tests failed" with the output discarded.
- `user-level-reference/skills/sync-template/SKILL.md` — six changes, all "clean" outcomes that were not: model-bump surfacing fires on `CLAUDE.local.md`, on a `settings.json` hook-list delta, and on any deleted `hooks/` file; a `has_conflicts: false` merge must be diffed for dropped lines and `bash -n`'d before it is applied (a three-way merge dropped the `LOG_FILE=` assignment from `hooks/read-size-gate.sh` in one repo and the closing `];` of an embedded JS array in `hooks/enforce-delegation.sh` in another, both reporting clean); accept-template is refused when the `PROJECT-CUSTOM` region is empty with project headings outside it, or when a `settings.json` matcher names agents the template version does not; step 6b collects sourced libs as well as `bash hooks/` entries; `TEMPLATE_DELETED` becomes an explicit ask with referenced/unreferenced evidence and a `git rm`, replacing the blanket "NEVER delete" (which still holds for project-owned files) and cross-referencing `~/.claude/hooks/`; the report carries a `verify-user-level-drift.sh` line. Plus: read the toolkit tree with Read/Grep, never the context-mode sandbox — `git -C` fails silently on its `/tmp` paths and `grep -c` returns 0.
- `templates/rust-tauri/.claude/rules/frontend.md` is framework-agnostic. It loads on every `src/**/*.ts` touch and was naming SolidJS and `vi.mock("../lib/tauri-api")` at projects using neither.

**Server-side, tracked separately in `mcp-dev-servers`:** the three-way merge dropping lines while reporting `has_conflicts: false`; `compute_status` omitting root-tracked `hooks/**` from `new_template_files`; the `AUTO_UPDATE`-hides-local-edits flag; stale placeholders; `LOCAL_MISSING` status for a gitignored absent file; and `get_diff` returning 91 KB for a 300-line file.

### By the numbers

| | v2.1 | v2.1.1 |
|---|---|---|
| consistency assertions | 172 | **205** |
| hook fixtures | 131 | **160** |

### Downstream migration

1. **Re-copy the whole hook mirror — `lib/` included — and the sync skill to `~/.claude/`.** The user-level copies are what run in repos without a project `hooks/` directory, and the `lib/` subdirectory is now **mandatory**: the gates exit 2 without it. Copying only the three scripts would hard-block every `git commit` and `git push` in every such repo.
   ```bash
   mkdir -p ~/.claude/hooks/lib
   cp -r user-level-reference/hooks/.               ~/.claude/hooks/
   cp -r user-level-reference/skills/sync-template  ~/.claude/skills/
   ```
   Verify before you rely on it: `ls ~/.claude/hooks/lib/git-cmd.sh`. If a gate ever prints `BLOCKED: … lib/git-cmd.sh missing`, this step was skipped or half-done.
2. **Add the `git-tools` deny entries** — `/sync-template` and accept `.claude/settings.json`, and copy the same seven `mcp__git-tools__*` deny lines into `~/.claude/settings.json`. If `git-tools` MCP is registered anywhere, **these deny entries are what keep the gates from being bypassable**. The alternative is to drop the server: `claude mcp remove git-tools -s user` — do it with the CLI, not by editing `~/.claude.json`, which Claude Code rewrites continuously (a Read→Edit round trip fails with "file has been modified since read").
3. **Restart the session after the sync, before any git push/merge/commit.** The rewritten gates are inert against the in-memory pre-sync `settings.json` until then. This is the one step that has no workaround. — superseded by v2.1.2 §1: hooks hot-reload, no restart is needed for the gates; agent definitions and skills still load per session, so restart before relying on updated agents/skills.
4. **Addendum to the v2.0 migration:** if a `# context-mode — MANDATORY routing rules` block keeps reappearing in your project `CLAUDE.md` below `PROJECT-CUSTOM:END`, nothing in this toolkit writes it — the **context-mode plugin** does, from its own `configs/claude-code/CLAUDE.md`, re-appended by its SessionStart auto-injection every session. Checked the plugin cache at `~/.claude/plugins/cache/context-mode/context-mode/1.0.162/`: **no opt-out env var or config toggle was found** in its README or its `hooks/*.mjs`. The only fix is to turn the plugin off — `claude plugin disable context-mode@context-mode`.

## v2.1 — 2026-08-29

**Two rules deleted, one judgement call added.** v2.0 was a measurement release; v2.1 is an alignment one. Boris Cherny, June 2026: *"I don't use plan mode anymore… starting with 4.6, and definitely with 4.7, it just doesn't need it."* The toolkit's plan gate encoded the opposite assumption, and so did a pinned session `effortLevel` — Anthropic's model-config docs now call `xhigh` *"the new default reasoning level"* for Opus 4.7 and later, which made a pinned `medium` a cap rather than a setting. Both are gone. What arrives in their place is not a third mechanism but a phrase: when a task is too big for one pass, the PO says **"use a workflow"** and Claude scripts its own fan-out. Detail per part is in the `v2.1-prN` entries below; this entry consolidates the migration.

### What changed

**PR7 — the plan gate is gone** ([#58](https://github.com/dagonet/claude-code-toolkit/pull/58), `6c2e64f`). `hooks/tier-before-coder.sh` refused a coder spawn unless a file in `docs/plans/` carried `Tier: T[1-4]` and challenge evidence — which made the plan file a password rather than a document. Deleted, not loosened. **Task Brief Upfront** replaces it as prose: every spawn prompt states goal, constraints, acceptance criteria, files in scope, and what "done" means. An agent that has to go looking for one of the five is under-briefed — a prompt defect, not an agent failure. Plan files stay useful and become optional. Verify: 174 → 172 assertions.

**PR8 — effort defaults to the model; the orchestrator model is a written choice** ([#59](https://github.com/dagonet/claude-code-toolkit/pull/59), `be13797`). `effortLevel` is removed from `user-level-reference/settings.json` — **unset means the model's default**. Effort is raised only where judgement happens: `architect` and `code-reviewer` go `high` → **`xhigh`**; coders and testers stay `medium`; `Explore` and `doc-generator` stay `low`. Alongside it, a documented model policy — **`/model fable` for T3/T4 sessions, Opus for T1/T2** — on the strength of Cherny on Fable 5 (*"the best model I have used for coding, by a wide margin… higher trust & autonomy"*) balanced against roughly 2× Opus price. Guidance, not a mechanism: the user picks with `/model`.

**PR9 — "use a workflow", a nightly routine, and the promised deletions.** Cherny and Cat Wu on dynamic workflows (May 28 + Jun 9 2026): the trigger phrase is exactly **"use a workflow"**, the orchestrator fans out implementer → two verifiers → fixer per task, and you *"default to auto mode so Claude isn't stopping for permissions"*. It is for **one task too big for a single pass** — a multi-module migration, a sweep across many files, competing hypotheses — and explicitly not for sequential work or several tasks on the same file, both of which break the independence a wave assumes. The merge gate is untouched: a workflow's branch rebases and gates like any other. Routines are the other half of the same distinction — *recurring maintenance*, where a workflow is one complex task — so this PR also ships `user-level-reference/routines/toolkit-nightly-check.md`, a **cloud** routine prompt (created with `/schedule` or at claude.ai/code/routines) that clones this repo daily, runs both verify scripts plus a stale-reference grep and a `VERSION`-vs-tag check, stays **silent on success**, and otherwise keeps one rolling `nightly-check: <date>` issue open. A routine runs over a clone and cannot reach `~/.claude` or uncommitted files, so everything it cannot see went into a local counterpart instead: the new **`retro-review` skill** reads the per-project retro ledger, runs `verify-user-level-drift.sh`, and lists sibling checkouts behind this repo's `VERSION`. Both are read-only; neither pushes.

**Also in PR9:** the two v2.0 no-op stubs are deleted as announced (below), and four review minors carried from PR7/PR8 are fixed — the appendix plan template's `Tier:`/`Team:` lines are annotated as parsed by nothing, both Lean Dev Prompt templates now carry the five Task-Brief headings and a `## Required Skills` block, check 6's absence grep no longer passes vacuously on a missing file, and a new assertion pins every agent's `effort:` and `model:` to the documented value lists — the PR8 probe showed the CLI accepts `effort: banana` without a warning, so nothing else was catching a typo.

### By the numbers

| | v2.0 | v2.1 |
|---|---|---|
| `hooks/*.sh` | 15 (incl. 2 no-op stubs) | **12** |
| skills | 7 | **8** |
| routines | 0 | **1** |
| consistency assertions | 174 | **172** |
| hook fixtures | 133 | **131** |
| always-loaded on `general` | 25,814 B | **25,999 B** (−36.8% vs the 41,167 B baseline) |

The always-loaded surface grew by 185 B, and that is deliberate: the *Pick the session model* bootstrap step and the `use a workflow` line are both decisions taken before any file is open, which is where always-loaded text earns its cost. No cut was invented elsewhere to keep the −37% headline round. Every figure here is `wc -c` / a counted script run on this commit, not carried forward.

### Downstream migration

1. **Run `/sync-template`** and accept `AGENT_TEAM.md`, `CLAUDE.md`, and `.claude/settings.json`. The root-tracked `hooks/tier-before-coder.sh`, `hooks/block-bash-vcs.sh`, and `hooks/require-teammate-report.sh` show up as template **deletions** — accept those too.
2. **User level, once per machine:**
   ```bash
   rm -f ~/.claude/hooks/tier-before-coder.sh \
         ~/.claude/hooks/block-bash-vcs.sh \
         ~/.claude/hooks/require-teammate-report.sh
   ```
   and delete any `settings.json` matcher group that still invokes one of them. Do the two together: those entries are 127-wrapped fail-closed, so an entry left behind after the script is gone blocks every call on its matcher — for the `Agent` matcher that means **every agent spawn**.
3. **Remove `"effortLevel"` from `~/.claude/settings.json`** to inherit the model's default. Keeping it breaks nothing; it just caps you below the model's own default.
4. **Re-copy the two agents and the new skill:**
   ```bash
   cp    user-level-reference/agents/architect.md      ~/.claude/agents/
   cp    user-level-reference/agents/code-reviewer.md  ~/.claude/agents/
   cp -r user-level-reference/skills/retro-review      ~/.claude/skills/
   ```
5. **Optional:** create the `toolkit-nightly-check` routine — `/schedule` from a toolkit checkout, or claude.ai/code/routines. Paste the prompt body from `user-level-reference/routines/toolkit-nightly-check.md` and give it GitHub issue write access. Nothing in the toolkit depends on it existing.
6. **Habit changes, not config:** `/model fable` at the start of a T3/T4 session, Opus otherwise; put the five-part task brief in every spawn prompt; say **"use a workflow"** when a task is too big for one pass.

Then start a new session — settings, skills, and agent definitions load per session.

### Removed

- `hooks/tier-before-coder.sh` (PR7) — the plan gate; superseded by the task brief in the spawn prompt.
- `hooks/block-bash-vcs.sh` and `hooks/require-teammate-report.sh` (PR9) — the two v2.0 no-op stubs, kept non-empty for exactly one release so a downstream `settings.json` still naming them would not fail closed on an exit 127. That release has shipped. Both were unregistered, so neither the hook-ref invariant nor the mirror check is affected.

### Known minor follow-ups

Carried from the v2.0 list plus this cycle's ledger, minus what was fixed since. **None are implemented in this release** — they are recorded so the omissions read as deliberate. Fixed here and therefore dropped from the carried list: `docs/architecture.md`'s Session Bootstrap step drift (PR8 fix round), `docs/workflow-audit.md`'s stale T1 row, and the four PR7/PR8 review minors described above.

*From v2.0 PR1:*

- `gc_protect_c_paths` regex also encodes non-git `-C "a b"` args (grep/diff) in the same segment — harmless, scope to `git … -C`.
- 12 processes per Bash call (3 node calls per gate × 3 gates) — consolidate `gc_read_stdin` into one `node -e`.
- unanchored commit match makes `grep "git commit"` run the full test suite — skip segments whose first token is echo/grep/rg/printf.
- drop unverified `_note_git_tools` key from `user-level-reference/.mcp.json.template`.

*From v2.0 PR2:*

- raw agent_type/agent_id interpolation into ledger row (strip `\r\n|`, slice 64).
- retro-ledger slurps whole transcript (`readFileSync`) — stream or size-cap.
- the mandate assertion compares mismatched sets (exclude coders consistently; include user-level agents).

*From v2.0 PR3:*

- read-size-gate offset advice off-by-one when offset absent (advise 501).
- bash-output-guard `mkdir -p` runs on every Bash call; no log pruning (`find -mtime +7 -delete`).

*From v2.0 PR4:*

- `## Working Preferences` heading now near-empty (rename/fold).
- duplicated formatter line inside python/java/csharp rules.
- further diet candidates — Compact Instructions (~1.6 KB) and Workflow TL;DR tier table (duplicated in AGENT_TEAM.md).
- dotnet/dotnet-maui CLAUDE.md have no `## Quick Start`.
- rust-tauri Quick Start uses literal commands because setup-project derives none for that variant — derive them (cargo build/test/fmt/clippy), then switch to placeholders.
- `tools/measure-context-bloat.py` needs `PYTHONIOENCODING=utf-8` on Windows.

*From v2.0 PR5:*

- `verify-user-level-drift.sh` red-by-design — add `--expect-drift`/WARN mode.
- "PR1 removed…" jargon in `skills/commit/SKILL.md:9`.
- `challenge` skill made explicit-only (`disable-model-invocation`) — was 2nd-most-used command; consider splitting guidance (auto) from architect spawn (explicit).

*New in v2.1:*

- `docs/architecture.md` §Session Bootstrap step 5 names MCP tools (`git_status`, `git_worktree_list`) where the templates name the CLI (`git status`) — cosmetic drift between two descriptions of the same step.
- Nothing asserts the `use a workflow` phrase or the routine/skill pair — they are prose and a prompt, and no hook reads either. A future verify check could at least pin that the phrase still appears in all six `AGENT_TEAM.md` copies.
- `toolkit-nightly-check.md` is a prompt body a human pastes into `/schedule`; there is no mechanism keeping the pasted routine in sync with the file after that.

## v2.1-pr8 — 2026-08-29

**Stop setting a session effort level; spend the effort where judgement happens.** Anthropic's model-config docs now describe `xhigh` as *"the new default reasoning level"* for Opus 4.7 and later, and the Claude 5 generation models decide per step how hard to think. A pinned `effortLevel: medium` at session level therefore capped the model below its own default on every turn, for no measured benefit. It is removed from `user-level-reference/settings.json` — **unset means the model's default**. Effort is now raised only where it pays: `architect` and `code-reviewer` move `high` → **`xhigh`**, coders and testers stay `medium`, `Explore` and `doc-generator` stay `low`.

**Orchestrator model is a per-session choice, and the choice is written down.** Boris Cherny, June 9 2026, on Fable 5: *"the best model I have used for coding, by a wide margin… higher trust & autonomy."* That advantage shows up on long, multi-file, architectural sessions — and Fable is roughly **2× Opus price**, so it is not the blanket default. The documented policy: **`/model fable` for T3/T4 sessions, Opus for T1/T2**. It is guidance, not a mechanism — the user picks with `/model`; nothing enforces it. The diagnostic rule is unchanged and now sits next to it: wrong despite full context → bigger model; skipped files or tests not run → raise effort.

**Probe note.** `effort: xhigh` was checked against a throwaway project agent before the change: `claude -p --agent` returned a normal response with no frontmatter warning, and `claude plugin validate` passed. Both, however, also accepted a deliberately invalid `effort: banana` — the CLI does **not** validate this field, so the probe proves nothing beyond "no crash". `xhigh` ships on the strength of the documented level list (`low` / `medium` / `high` / `xhigh`), not the probe.

**Files:** `user-level-reference/settings.json` (`effortLevel` removed); `user-level-reference/settings-reference.md` (mirrored JSON + the `alwaysThinkingEnabled`, *Model & Effort*, and `advisorModel` prose); `templates/*/.claude/agents/{architect,code-reviewer}.md` ×12 and `user-level-reference/agents/{architect,code-reviewer}.md` ×2 (`effort: xhigh`); `templates/*/AGENT_TEAM.md` ×6 (*Model & Effort Policy*, still byte-identical); `templates/*/CLAUDE.md` ×6 (Session Bootstrap gains a step 2, *Pick the session model* — it has to precede the work it governs, so it sits right after assuming the PO role, not after the spawn); `README.md`, `docs/architecture.md` (policy paragraph, and its §Session Bootstrap list resynced to the same 7 steps in the same order — it had drifted to 5), `user-level-reference/README.md`. `scripts/verify-template-consistency.sh` unchanged — **no assertion pinned an effort value**, so the total stays at **172**; `scripts/test-hooks.sh` unchanged (133 passed).

### Downstream migration

1. Remove `"effortLevel"` from `~/.claude/settings.json` to inherit the model's default — or keep it if you deliberately want a fixed level; nothing breaks either way.
2. Re-copy `agents/architect.md` and `agents/code-reviewer.md` from `user-level-reference/agents/` into `~/.claude/agents/` (only the `effort:` line changed).
3. Run `/sync-template` in template-consuming repos and accept `AGENT_TEAM.md`, `CLAUDE.md`, and the two agent files.
4. Habit change: `/model fable` at the start of a big (T3/T4) session, Opus otherwise. Fable costs about twice as much per token — the payoff is fewer steers over a longer session, not a cheaper one.

## v2.1-pr7 — 2026-08-29

**The plan gate is gone.** Boris Cherny, June 2026: *"I don't use plan mode anymore… starting with 4.6, and definitely with 4.7, it just doesn't need it."* The models the toolkit targets do not need a staged planning ritual — they need the whole task in the prompt. `hooks/tier-before-coder.sh` enforced the opposite: a coder spawn was refused unless a file in `docs/plans/` carried `Tier: T[1-4]` and challenge evidence, which made the plan file a password rather than a document. It is deleted, not loosened; a hardened version was on the roadmap (`docs/workflow-audit.md` W1, follow-up PR B) and that roadmap item is superseded.

What replaces it is prose, not another mechanism: **Task Brief Upfront** in `AGENT_TEAM.md`. Every spawn prompt states goal, constraints, acceptance criteria, files in scope, and what "done" means (tests + `bash hooks/run-gate.sh`). An agent that has to go looking for one of the five is under-briefed — a prompt defect, not an agent failure. Plan files in `docs/plans/` stay useful and become optional: write one when the work spans sessions or records a decision. `/challenge` stays as an optional skill for architectural work.

Unchanged on purpose: `hooks/require-skills-block.sh` (the `## Required Skills` spawn contract), `hooks/enforce-delegation.sh` (the PO never does hands-on work), the tier table as **size caps** for team composition, and the review/tester/merge-gate pipeline.

**Files:** deleted `hooks/tier-before-coder.sh` and `user-level-reference/hooks/tier-before-coder.sh`; the `Agent` → tier hook entry dropped from `templates/*/.claude/settings.json` ×6 and `user-level-reference/settings.json`; `templates/*/AGENT_TEAM.md` ×6 (Plan Challenge Protocol → Task Brief Upfront, architect lifecycle, sprint-planning flow, Rule 13); `templates/*/CLAUDE.md` ×6 (bootstrap step 6, TL;DR); `scripts/verify-template-consistency.sh` (check 6 inverted to assert the gate vocabulary is absent; check 1 removed as subsumed — **174 → 172 assertions**); `scripts/check-activation.sh`; `hooks/require-skills-block.sh` (stale comment); `README.md` (**15 → 14 hook scripts**, counts recomputed); `docs/architecture.md`, `docs/templates.md`, `docs/workflow-audit.md`, `docs/hook-enforcement-ideas.md`, `user-level-reference/{README,CLAUDE,settings-reference}.md`, `user-level-reference/skills/karpathy-guidelines/SKILL.md`. `scripts/test-hooks.sh` unchanged — the gate never had fixtures (133 passed, still 133).

### Downstream migration

1. Run `/sync-template` and **accept** the changes to `AGENT_TEAM.md`, `CLAUDE.md`, and `.claude/settings.json`. The root-tracked `hooks/tier-before-coder.sh` shows up as a template deletion — accept that too.
2. At user level: `rm ~/.claude/hooks/tier-before-coder.sh` and delete its `Agent` matcher entry from `~/.claude/settings.json`. Do them together — the entry is 127-wrapped fail-closed, so an entry left behind after the script is gone blocks **every** agent spawn.
3. No plan file is required before spawning coders any more. Put the task brief in the spawn prompt instead; keep writing plan files where they earn their keep.

## v2.0 — 2026-08-29

**Six weeks of transcripts, read instead of guessed at.** Every change below was proposed by a measurement, not by a preference: a hook that blocked 1,240 turns to buy nothing, a stall mode that only ever affected named teammates, 219 exploration spawns billed at Opus, ~400 calls to tools the calling agent did not have, 12 skills invoked 0 times. The direction is the same in all five parts — **let a mechanism enforce what prose used to repeat, and load the prose only when it is actionable.** Always-loaded config on `general`: **41,167 → 25,814 B (−37%)**, measured with `wc -c` on the shipped files rather than carried forward. Detail for each part is in the `v2.0-prN` entries below; this entry consolidates the migration.

### What changed

**PR1 — the git ban became a git gate** ([#52](https://github.com/dagonet/claude-code-toolkit/pull/52), `0da3f1d`). `hooks/block-bash-vcs.sh` blocked **1,240 turns in six weeks** and bought nothing: the three git gates keyed on `mcp__git-tools__*` tool names only because Bash git was banned in the first place, so the ban was load-bearing for its own workaround. Claude Code 2.1.250 PreToolUse hooks can read `tool_input.command` and deny with exit 2, so the gates now parse the command itself — a new shared parser `hooks/lib/git-cmd.sh` splits on `&&`/`||`/`;`/`|`, unwraps `bash -c` and `pwsh -Command`, and honours `git -C`. The CLI is allowed and *gated*: a red-gate commit, a push to main, and an ungated merge still stop. `scripts/test-hooks.sh` arrived with it — 46 stdin fixtures over throwaway git repos, including every must-**not**-block case. **`git-tools` MCP is optional from here on**, and work routed through it bypasses the gates.

**PR2 — agent teams retired; parallelism comes from the Agent tool** ([#53](https://github.com/dagonet/claude-code-toolkit/pull/53), `6b3b144`). Every "sub-agent stalled without returning" complaint in the window traced back to a *named teammate*; the **1,777 Agent-tool spawns** in the same window never stalled once. Agent teams are experimental and off by default, `TeamCreate`/`TeamDelete` no longer exist, and `team_name` is deprecated — so the toolkit stops depending on them. `AGENT_TEAM.md` lost its naming convention and gained a final-message contract; long tasks use `background: true`. What did **not** change: the PO still never does hands-on work, and `hooks/enforce-delegation.sh` is untouched. New in its place: a **retro ledger** (`retro-ledger.sh` on `SubagentStop`, `retro-brief.sh` on `SessionStart`) that records each failing subagent run to the project's auto-memory and replays the last ten at the next session start, so a broken `tools:` allowlist surfaces once instead of every session.

**PR3 — every agent declares what it costs** ([#54](https://github.com/dagonet/claude-code-toolkit/pull/54), `dd2cd8e`). The orchestrator ran on Opus, workers on `sonnet`, Haiku almost unused, and the *built-in* `Explore` inherited the session model — **219 exploration spawns at Opus prices**. In the same window **~400 tool calls hit tools the calling agent did not have** (`dotnet-tools`: 87 of 87 failed, advertised in the agent body and absent from its `tools:`) and **5,032 of 10,336 `Read` calls passed no `limit`**. So: `model:` + `effort:` on every agent, aliases only; a custom `Explore` pinned to haiku in all seven locations; `Skill` added to the 54 agents told to invoke skills (the `## Required Skills` block had been dead for coders); a tool-allowlist invariant asserted by the verify script. `read-size-gate.sh` stopped blocking and started **capping** — it rewrites an unbounded `Read` to `limit: 500` and names the next offset — and `bash-output-guard.sh` head/tail-truncates any Bash stream over 12,000 chars to a log file. Both native, both replacing a routing contract the model had to remember.

**PR4 — CLAUDE.md is facts; conventions are path-scoped** ([#55](https://github.com/dagonet/claude-code-toolkit/pull/55), `549453c`). A C# style rule was loading on every turn of every session, including the ones that never opened a `.cs` file. Seven `.claude/rules/*.md` files with a `paths:` frontmatter glob list now carry those conventions and load only when Claude touches a matching file, re-injected after compaction. Only `paths:`-scoped rules ship — an unconditional rule is always-loaded context wearing a `rules/` filename. A second round routed two more sections by **audience**: *Open Brain Context for Agents* duplicated `AGENT_TEAM.md` (on-demand, more detailed), and *Working Preferences* binds developer agents, not the PO, so its 11 bullets moved into the `karpathy-guidelines` skill that all 12 coders preload. `general` CLAUDE.md **13,892 → 10,362 B**; across all six, 94,467 → 64,837 B (−31%). The revised ≤ 9 KB target was **not** met and no further cut was invented to reach it.

**PR5 — commands became skills, and most of them stopped existing** ([#56](https://github.com/dagonet/claude-code-toolkit/pull/56), `6f72a06`). The toolkit's 12 skills were invoked **0 times** in the measured window and its 23 slash commands close to it; all 493 measured skill invocations went to `superpowers:*` and `karpathy-guidelines`. Anthropic has since made `.claude/commands/<n>.md` equivalent to `.claude/skills/<n>/SKILL.md`, so there is one artifact type to keep instead of two: **23 commands + 12 skills → 7 skills, no `commands/` directory**. `/build` and `/test` were already redundant with the `Gate:` mechanism; `/skill-eval` + `/skill-improve` were replaced by the official `skill-creator` plugin. The user-level `CLAUDE.md` lost its `# context-mode — MANDATORY routing rules` block (8,637 → 5,089 B, −41%): it mandated `ctx_batch_execute`, which **failed 28.6% of its calls**, and subagents made **164 calls to `ctx_*` tools they do not have** — the block was being inherited into prompts where it was pure hallucination bait.

**PR6 — this release.** `VERSION`, this roll-up, a docs sweep, and one item PR1–PR5 surfaced: `user-level-reference/hooks/` now **mirrors** the fail-closed hooks (`no-push-main.sh`, `tier-before-coder.sh`, `pre-commit-test.sh`, `gate-before-merge.sh`, `lib/git-cmd.sh`) byte-for-byte from the toolkit root, so the user-level install is one `cp -r` instead of a two-directory scavenger hunt. A new glob-derived assertion fails the build if any mirrored file drifts from its root original — a stale mirror would have enforced an older contract at user level than at project level, silently.

**This also repairs the user-level push gate.** The v2.0-pr5 copy step was `cp user-level-reference/hooks/*.sh` followed by `cp hooks/no-push-main.sh hooks/tier-before-coder.sh` — **neither glob recurses, and `lib/git-cmd.sh` was in neither source set**, so anyone who followed it installed a v2.0 `no-push-main.sh` that cannot load the parser it sources on its first line. The failure is quiet: the script file *exists*, so the wrapper's `127 → exit 2` fail-closed path never fires. If you already copied the hooks under the pr5 instructions, re-run step 4 below and confirm `~/.claude/hooks/lib/git-cmd.sh` is present.

### By the numbers

| | v1.5 | v2.0 |
|---|---|---|
| `hooks/*.sh` | 13 | **15** (incl. 2 no-op stubs) |
| agent definitions (6 variants + user-level) | 61 | **68** |
| skills | 12 | **7** |
| slash commands | 23 | **0** |
| `templates/general/CLAUDE.md` | 13,892 B | **10,362 B** |
| always-loaded on `general` | 41,167 B (baseline) | **25,814 B** (−37%) |
| consistency assertions | 131 | **174** |
| hook fixtures | 0 | **133** |

### Downstream migration

Five steps. Steps 1–3 are per project; step 4 is once per machine; step 5 is once per machine.

1. **Run `/sync-template` and accept the template version** of `CLAUDE.md`, `AGENT_TEAM.md`, `.claude/agents/*` (including the new `Explore.md`), `.claude/settings.json`, and the new `.claude/rules/*.md`. `CLAUDE.md` will report **CONFLICT** for any project with local edits — accept the template, then re-paste your customisations between the `PROJECT-CUSTOM:BEGIN/END` markers, which the sync server preserves verbatim. If your project already had language conventions pasted into `CLAUDE.md`, delete them there once the rules land, or the same text loads twice.
2. **Delete the plugin-installed `# context-mode — MANDATORY routing rules` block from every project `CLAUDE.md`** you own, including projects bootstrapped from an earlier toolkit version. The context-mode plugin is optional now; if you still run it, its own SessionStart hook supplies its guidance, and the native `Read` cap and Bash output guard do the same job without a contract the model has to remember.
3. **If your `settings.json` was locally modified**, `/sync-template` will not rewrite it. By hand: delete the whole `TeammateIdle` block and the `PreToolUse` matcher that invokes `block-bash-vcs.sh`, then add the four v2.0 entries — `PreToolUse` `"Bash|PowerShell"` running the three git gates in order, `PostToolUse` `"Bash|PowerShell"` → `bash hooks/bash-output-guard.sh`, `SubagentStop` → `bash hooks/retro-ledger.sh`, and `SessionStart` → `bash hooks/retro-brief.sh`. The last three go in **without** the 127 wrapper: they cannot block, so wrapping them would only invent a failure mode. Copy the shape from `templates/general/.claude/settings.json`.
4. **User level (`~/.claude/`), once per machine.**
   ```bash
   cp    user-level-reference/CLAUDE.md      ~/.claude/CLAUDE.md
   cp    user-level-reference/settings.json  ~/.claude/settings.json
   cp -r user-level-reference/skills/.       ~/.claude/skills/
   cp -r user-level-reference/agents/.       ~/.claude/agents/
   cp -r user-level-reference/hooks/.        ~/.claude/hooks/
   rm -rf ~/.claude/commands/
   rm -rf ~/.claude/skills/{arch-analyze,code-review,explaining-code,fix-errors,impact-analysis,orient,refactor,security-audit}
   rm -f  ~/.claude/hooks/allow-ctx-plan.sh
   ```
   The single `cp -r` of `hooks/` **supersedes the two-step copy in v2.0-pr5** — the fail-closed hooks are mirrored into this directory as of PR6, and unlike the two `*.sh` globs it took, `cp -r` carries `lib/git-cmd.sh` across. Verify with `ls ~/.claude/hooks/lib/git-cmd.sh`: the three git gates source it on their first line, and without it the user-level push gate silently cannot evaluate a command. Deleting `~/.claude/commands/` is not optional: a leftover command file shadows its skill. Then, in `~/.claude/settings.json`: **add a `permissions.autoMode.environment`** describing your machine's trust boundary in prose (`defaultMode: auto` routes undecided calls through a classifier and `environment` is what it reasons over; `autoMode` is **User/managed scope only**, so a project cannot ship one — the right polarity, since a hostile repo must not widen its own trust), **delete `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`**, remove the `allow-ctx-plan.sh` matcher group, and **remove the `git-tools` MCP server from `~/.claude.json` if you do not use it directly** — nothing in the toolkit requires it, and git routed through it bypasses the gates. If you run a model proxy, exempt the auto-mode classifier from it as you already do for `advisorModel`: 83 classifier outages were observed when it was proxied.
5. **Install `skill-creator@claude-plugins-official`** — it replaces `/skill-eval`, `/skill-improve`, and the toolkit's hand-rolled `evals/evals.json` convention with eval authoring, LLM grading, and benchmarking. `settings.json` already enables it.

Then **start a new session** — settings, skills, and agent definitions load per session. `setup-project.sh` / `.ps1` print the `autoMode.environment` line for you at the end of every run, dry or real.

Until steps 1–5 are done, `scripts/verify-user-level-drift.sh` reports DRIFT. That is expected, not a failure: the reference leads and the live copy follows. See [`docs/verification.md`](docs/verification.md) → *Verifying the toolkit repo itself*.

### Deprecated (removed in v2.1)

Both are **no-op stubs** — header plus `exit 0` — and both are unregistered. They stay non-empty for one release so that a downstream `settings.json` still naming them does not fail closed on an exit 127.

- `hooks/block-bash-vcs.sh` — superseded by the three command-parsing git gates (PR1).
- `hooks/require-teammate-report.sh` — the `TeammateIdle` gate; agent teams are retired (PR2).

### Known minor follow-ups

Carried verbatim from the implementation ledger. **None of the entries below are implemented in this release** — they are recorded so the omissions read as deliberate.

Four ledger entries *were* fixed here, because each was a dangling or contradictory reference in a **shipped artifact** rather than a nice-to-have, and are therefore not listed below:

- mirror `no-push-main.sh` + `tier-before-coder.sh` into `user-level-reference/hooks` — done, plus the two other gates and `lib/`.
- `Explore.md` (×7) named `hooks/agent-budget-warn.sh` by repo-relative path, which dangles at user level → now "the agent-budget-warn hook", no path.
- `templates/python/.claude/rules/python.md` listed `ruff.toml` in `paths:`, which no variant ships → dropped. `.editorconfig` added to both `python.md` and `java.md`, since each rule's text already calls it authoritative.
- `AGENT_TEAM.md` let the PO SendMessage a completed subagent while the agent mandate says "no side channel" → the paragraph now states the exception explicitly ("a follow-up question may arrive after you finish — answer it in a new final message. Nothing arrives *during* a run."). Byte-identity across all six variants preserved.

*From PR1:*

- `gc_protect_c_paths` regex also encodes non-git `-C "a b"` args (grep/diff) in the same segment — harmless, scope to `git … -C`.
- 12 processes per Bash call (3 node calls per gate × 3 gates) — consolidate `gc_read_stdin` into one `node -e`.
- unanchored commit match makes `grep "git commit"` run the full test suite — skip segments whose first token is echo/grep/rg/printf.
- drop unverified `_note_git_tools` key from `user-level-reference/.mcp.json.template`.

*From PR2:*

- raw agent_type/agent_id interpolation into ledger row (strip `\r\n|`, slice 64).
- retro-ledger slurps whole transcript (`readFileSync`) — stream or size-cap.
- verify `:889-891` mandate assertion compares mismatched sets (exclude coders consistently; include user-level agents).

*From PR3:*

- read-size-gate offset advice off-by-one when offset absent (advise 501).
- bash-output-guard `mkdir -p` runs on every Bash call; no log pruning (`find -mtime +7 -delete`).

*From PR4:*

- `## Working Preferences` heading now near-empty (rename/fold).
- duplicated formatter line inside python/java/csharp rules.
- further diet candidates — Compact Instructions (~1.6 KB) and Workflow TL;DR tier table (duplicated in AGENT_TEAM.md).
- dotnet/dotnet-maui CLAUDE.md have no `## Quick Start`.
- rust-tauri Quick Start uses literal commands because setup-project derives none for that variant — derive them (cargo build/test/fmt/clippy) in v2.1, then switch to placeholders.
- `tools/measure-context-bloat.py` needs `PYTHONIOENCODING=utf-8` on Windows.

*From PR5:*

- `verify-user-level-drift.sh` red-by-design — add `--expect-drift`/WARN mode.
- "PR1 removed…" jargon in `skills/commit/SKILL.md:9`.
- `challenge` skill made explicit-only (`disable-model-invocation`) — was 2nd-most-used command; consider splitting guidance (auto) from architect spawn (explicit).

## v2.0-pr5 — 2026-08-28

**Commands became skills, and most of them stopped existing.** In six weeks of transcripts the toolkit's 12 skills were invoked **0 times** and its 23 slash commands close to it — `/sync-template` 22, `/challenge` 10, `/commit` and `/sprint` a handful, the rest zero. All 493 measured skill invocations went to `superpowers:*` and `karpathy-guidelines`. Anthropic has since made `.claude/commands/<n>.md` equivalent to `.claude/skills/<n>/SKILL.md`, so there is one artifact type to keep instead of two. 23 commands + 12 skills → **7 skills, no `commands/` directory**.

### Skills: kept, migrated, deleted

- **Kept:** `sync-template`, `contribute-upstream`, `karpathy-guidelines` (its `## Toolkit working preferences (developer agents)` section from PR4 is untouched), `mcp-usage` (description trimmed 496 → 172 chars; its table of pointers to now-deleted skills was repointed at `/code-review` and `superpowers:*`).
- **Migrated command → skill:** `challenge`, `sprint`, `commit`. `$ARGUMENTS` works unchanged in a skill body. `commit` was rewritten for **native git** (`git add` / `git diff --cached` / `git commit`) since PR1 dropped the MCP-git mandate, keeping its verification checklist. `sprint` was rewritten for the **subagents-only** model from PR2: no teammate pings, `background: true` spawns, final-message reporting; rebase-before-merge and gate-before-merge rules kept.
- **`disable-model-invocation: true`** on all five explicit workflows — `sync-template`, `contribute-upstream`, `sprint`, `commit`, `challenge`. They run only when the user types the slash command, never on the model's initiative. `challenge` is on the list because its step 2 spawns the architect: a model-invocable skill that dispatches a subagent can start work the PO never planned, and `tier-before-coder.sh` sits on the same `Agent` matcher. Unprompted challenging is not lost — the Plan Challenge Protocol in every variant's `CLAUDE.md` already mandates it. Only `karpathy-guidelines` and `mcp-usage`, which are pure guidance, auto-trigger.
- **Deleted (skills):** `arch-analyze`, `code-review`, `explaining-code`, `fix-errors`, `impact-analysis`, `orient`, `refactor`, `security-audit`, including their `evals/` directories.
- **Deleted (commands):** `add-tests`, `api-design`, `arch-doc`, `build`, `coverage-report`, `dependency-audit`, `dotnet-analyze`, `ef-check`, `godot-run`, `issue-create`, `new-feature`, `nuget-audit`, `pre-release`, `skill-eval`, `skill-improve`, `spec-to-issues`, `tech-debt`, `test`, `traceability`, `user-story`. The `commands/` directory is gone.
- **What replaced them:** `/build` and `/test` → the `Gate:` mechanism (`bash hooks/run-gate.sh`), which already had to be the single source of build/test commands for `gate-before-merge.sh` to work. `/skill-eval` + `/skill-improve` and the hand-rolled `evals/evals.json` convention → the official **`skill-creator@claude-plugins-official`** plugin (flipped to `true` in `settings.json`), which ships eval authoring, LLM grading, and benchmarking. `fix-errors` → `superpowers:systematic-debugging`. `code-review` / `security-audit` → the bundled `/code-review` plugin and `superpowers:requesting-code-review`. `arch-analyze` / `impact-analysis` / `explaining-code` / `orient` → the `Explore` subagent plus `superpowers:writing-plans`.
- **No binding broke.** The `AGENT_TEAM.md` Spawn-Prompt Binding Table and `hooks/require-skills-block.sh` reference only `karpathy-guidelines` and `superpowers:*`; the `code-reviewer` row was already *(none — review is the agent's core job)*. `require-skills-block.sh` is therefore unchanged — and had to be, since `verify-template-consistency.sh` diffs it against the table.

### Reference sweep

Every prose reference to a deleted artifact was replaced or removed: `templates/*/CLAUDE.local.md` (`fix-errors` ×6 → `superpowers:systematic-debugging`; `security-audit` ×2 → `/code-review`), `docs/verification.md` (`/orient` → `/challenge` as the skill smoke-test; `/build` → `bash hooks/run-gate.sh`), `docs/architecture.md` and `README.md` inventory counts, and `user-level-reference/README.md` (rewritten). Remaining matches for the sweep regex are all non-references: `tech-debt` as a **GitHub issue label** in `github-issues` mode, `refactor` inside the conventional-commit list `feat/fix/refactor/test`, and one English "a refactor" in `Explore.md`.

### user-level CLAUDE.md — 8,637 → 5,089 B (−41%)

- **The `# context-mode — MANDATORY routing rules` block (65 lines) is gone.** It mandated `ctx_batch_execute` as the PRIMARY tool; that tool failed **28.6%** of its calls in the measured window. Worse, subagents made **164 calls** to `ctx_*` tools they do not have — the block was being inherited into prompts for agents where it was pure hallucination bait. Three lines replace it: the plugin is optional, its own SessionStart hook carries its guidance, and subagents have no `ctx_*` tools.
- **`ENABLE_TOOL_SEARCH` removed the original rationale.** MCP tool definitions are deferred by default now, so the tool-bloat problem context-mode was mitigating no longer exists at session start.
- **Two Platform bullets scoped to the main thread.** "MCP tools for release notes" and "use MCP GitHub tools, not `gh release create`" were unconditional, but subagents have no MCP servers — the same failure mode as the context-mode block (164 subagent calls to tools that were not there). Both now carry a `**PO / main thread only**` prefix.
- **Read & Search table de-ctx-ed:** analyze-one-file → `Read` with `limit`/`offset` (`hooks/read-size-gate.sh` caps at 500 lines and hands back the next offset), multi-file research → the `Explore` subagent on haiku. The 22%-of-context statistic keeps its single authoritative copy, now noting the cap is enforced mechanically.

### Toolkit root CLAUDE.md — 3,842 → 1,848 B

It was a verbatim copy of the context-mode block: zero repo-specific content in the repo's own always-loaded file. Replaced with toolkit facts — what the repo is, the six variants, the verify scripts as the gate, the byte-identity invariant and "edit general then `cp`", LF, the PowerShell/UTF-8 trap, and the `docs/plans/` convention.

### user-level settings.json

- **`autoMode.environment` added — as a top-level key**, a sibling of `permissions`, not nested inside it. `defaultMode: auto` (PR1) routes undecided calls through a classifier; `environment` is the prose it reasons over. Four lines: `$defaults` plus primary use, trusted repos, and what counts as a sensitive remote target. `autoMode` is **User/managed scope only** — a project cannot ship one, which is the right polarity: a hostile repo must not be able to widen its own trust.
- **Do not route the classifier through a model proxy.** 83 classifier outages were observed when it was; `cc-proxy` users must exempt it, as with `advisorModel`.
- `advisorModel: "opus"` added (top level). `settings-reference.md` documented it but the shipped file never set it.
- `skill-creator@claude-plugins-official` → `true`.
- `Bash(*)`, `WebFetch(*)`, `mcp__git-tools__*` confirmed absent (removed in PR1); `deny: Read(.env*)` kept. `CLAUDE_CODE_DISABLE_1M_CONTEXT` and `CLAUDE_CODE_AUTO_COMPACT_WINDOW` **kept and annotated** — they are not redundant on the MAX plan; dropping them clamps `/context` back to 200k. `alwaysThinkingEnabled` kept with a note that it has no effect on Fable 5.
- `settings-reference.md`: the *Full Settings JSON* block was three PRs stale (it still showed `Bash(*)`, `defaultMode: dontAsk`, and 14 enabled plugins) — it is now taken verbatim from the shipped file. Hook section rewritten for the v2.0 set (`no-push-main`, `tier-before-coder`, `bash-output-guard`, `read-size-gate`) with `block-bash-vcs` marked retired at user level, and `ENABLE_TOOL_SEARCH` documented as the replacement for context-mode's tool-bloat rationale.

### Downstream migration

Copy from `user-level-reference/` in this repo to `~/.claude/`:

```bash
cp    user-level-reference/CLAUDE.md      ~/.claude/CLAUDE.md
cp    user-level-reference/settings.json  ~/.claude/settings.json
cp -r user-level-reference/skills/.       ~/.claude/skills/
cp -r user-level-reference/agents/.       ~/.claude/agents/
cp    user-level-reference/hooks/*.sh     ~/.claude/hooks/
cp    hooks/no-push-main.sh hooks/tier-before-coder.sh ~/.claude/hooks/
```

Then:

1. **`rm -rf ~/.claude/commands/`** — every surviving command is a skill now, and a leftover command file shadows its skill.
2. **Delete the removed skill directories:** `rm -rf ~/.claude/skills/{arch-analyze,code-review,explaining-code,fix-errors,impact-analysis,orient,refactor,security-audit}`.
3. **Install `skill-creator@claude-plugins-official`** for eval authoring and grading (`settings.json` already enables it).
4. **Remove the `# context-mode — MANDATORY routing rules` block from every project `CLAUDE.md`** you own, including projects bootstrapped from an earlier toolkit version. If you still run the plugin, its SessionStart hook supplies its own guidance.
5. Start a new session — settings and skills load per session.

Until step 1–5 are done, `scripts/verify-user-level-drift.sh` will report DRIFT. That is expected: the reference leads, the live copy follows.

## v2.0-pr4 — 2026-08-28

**CLAUDE.md is facts; conventions are path-scoped.** A C# style rule was being loaded on every turn of every session, including the ones that never opened a `.cs` file. `.claude/rules/*.md` files with a `paths:` frontmatter glob list load only when Claude reads or edits a matching file, and are re-injected after compaction — so the conventions arrive exactly when they are actionable.

### Path-scoped rules (new, 7 files; 1,224–2,270 B per variant)

- `templates/dotnet/.claude/rules/csharp.md` — `**/*.cs`, `**/*.csproj`, `**/*.props`, `**/*.targets`, `.editorconfig`.
- `templates/dotnet-maui/.claude/rules/csharp.md` (same globs) + `xaml.md` — `**/*.xaml`, `**/*.xaml.cs`, carrying the CommunityToolkit.Maui and ContentPage-namespace checks.
- `templates/rust-tauri/.claude/rules/rust.md` — `**/*.rs`, `rustfmt.toml`, `Cargo.toml`; `frontend.md` — `src/**/*.ts`, `src/**/*.tsx`, `**/*.css`, `.prettierrc`. The single Rust+TypeScript *Code Style* section was split along the language boundary so each half is scoped to the files it governs.
- `templates/java/.claude/rules/java.md` — `**/*.java`, `pom.xml`, `**/build.gradle*`, `src/main/resources/application.*`.
- `templates/python/.claude/rules/python.md` — `**/*.py`, `pyproject.toml`, `requirements*.txt`, `ruff.toml`.
- **Only `paths:`-scoped rules ship.** An unconditional rule loads at launch at CLAUDE.md cost — it is always-loaded context wearing a `rules/` filename, and buys nothing. `general` has no language of its own and therefore ships no rules; its CLAUDE.md says where conventions belong instead.
- `{{FORMAT_COMMAND}}` / `{{LINT_COMMAND}}` placeholders survive the move: `setup-project.sh` / `.ps1` walk `.claude/` recursively and run `apply_replacements` on every copied file, so rules are populated and manifest-tracked like any other template file.

### CLAUDE.md diet (×6)

- **Spawn-Prompt Binding Table deleted.** It duplicated `AGENT_TEAM.md` → *Spawn-Prompt Binding Table* and is enforced by `hooks/require-skills-block.sh`, which reads neither copy. One pointer line remains.
- *Code Style (MANDATORY)*, *Enforcement Notes*, and the per-variant *Project Conventions* sections moved verbatim into rules, each replaced by `Conventions: see .claude/rules/<name>.md (loads when you touch matching files).`
- Gate rule and commit checklist compressed to name the enforcing hook once instead of restating what it does.
- Emphasis rationed: `# Session Bootstrap (MANDATORY)` → `# Session Bootstrap`, "The PO MUST use `EnterPlanMode`" → "the PO calls `EnterPlanMode`", "Every plan MUST declare its tier" → "Every plan declares its tier". The one surviving shouted line is the Superpowers header, which two hooks and the verify script pin.
### CLAUDE.md diet, round 2 — routed by audience

Two more sections left the always-loaded set once the question changed from "is this important?" to "**who** needs it, and **when**?".

- **`## Open Brain Context for Agents` deleted** (×6). Every claim it made — spawned agents cannot reach Open Brain, search before spawning, capture decisions with rationale and bug root causes, skip routine outcomes — is already stated, in more detail and with per-agent tables, in `AGENT_TEAM.md` §Open Brain (moved there in v1.4). CLAUDE.md keeps one line: `Open Brain search/capture guidance for spawns: AGENT_TEAM.md §Open Brain.` `AGENT_TEAM.md` is unchanged and still byte-identical across all six variants.
- **`## Working Preferences` bullets moved into the `karpathy-guidelines` skill** as `## Toolkit working preferences (developer agents)`. The section's own actor note says these bind **developer agents**, not the PO — and all 12 coders preload the skill (`skills: [karpathy-guidelines]`, added in PR3), so the preferences now arrive at spawn, in the context that acts on them, at zero always-loaded cost. CLAUDE.md keeps the `Enforced mechanically:` line (PO-relevant) plus one pointer.
- **Bytes:** general 13,892 → 12,522 → **10,362** · dotnet 15,450 → **10,612** · dotnet-maui 15,699 → **10,651** · java 16,378 → **10,945** · python 16,299 → **10,971** · rust-tauri 16,749 → **11,296**. Always-loaded total on `general`: **32,888 → 29,358 B**, and **41,167 → 29,358 (−29%)** against the pre-trim baseline. Total across the six CLAUDE.md files: 94,467 → 64,837 B (−31%).
- The revised **≤ 9 KB target was not met** — the two moves yielded 2.2 KB and land the variants at 10.3–11.3 KB. What remains is the §B keep-list (Session Bootstrap, Workflow TL;DR, Superpowers, Quick Start, Build & Test, Verification, Debugging, Commit Workflow, Compact Instructions) plus the PROJECT-CUSTOM region. No further cut was invented to reach the number.

### Verification (round 2)

- No *existing* assertion needed changing: grepping `scripts/`, `hooks/`, `tools/`, and both setup scripts for `Open Brain Context for Agents` and `Working Preferences` returned zero hits, so nothing pinned either heading.
- **New check 20 — working-preferences custody.** Moving prose out of the always-loaded set also moves it out from under every existing check, and the 11 developer-agent preferences now live in exactly one file that nothing referenced. Check 20 asserts the `## Toolkit working preferences` heading exists in `user-level-reference/skills/karpathy-guidelines/SKILL.md`, that the section holds at least 11 bullets (the v1.5 post-trim floor, parsed from the section — no line numbers, no bullet text, so adding a preference passes and losing one fails), and that all 6 CLAUDE.md files still name the skill. 159 → 167 assertions.
- The CLAUDE.md pointer now reads "see `AGENT_TEAM.md` → *Spawn-Prompt Binding Table*". It briefly said "see `## Required Skills`" — an anchor that no longer exists in CLAUDE.md, since this PR cut the table that defined it. The new target is pinned by check 4.
- Suite green, including the Superpowers header, the `superpowers:` token, the `PROJECT-CUSTOM` region, the banned-phrase sweep over `templates/*/CLAUDE.md`, and AGENT_TEAM.md byte-identity ×6.

### Verification

- `scripts/verify-template-consistency.sh` §19 (new, 3 assertion groups, all glob-derived): every non-`general` variant ships ≥ 1 `.claude/rules/*.md`; every rules file carries a `paths:` list with at least one glob; every such variant's CLAUDE.md still points at `.claude/rules/`. 148 → 159 assertions (→ 167 with §20 below).
- The dangling-`VERIFICATION_PLAYBOOK.md` fix in the plan was **not applied — the premise was wrong.** The file ships in all 6 variants and `setup-project.sh` copies it; the reference resolves in a generated project.

### Downstream migration

- `/sync-template` reports `CLAUDE.md` as **CONFLICT** for any project with local edits outside the `PROJECT-CUSTOM` region. Accept the template version, then re-paste your customisations between the `PROJECT-CUSTOM:BEGIN/END` markers — that region is preserved verbatim by the sync server.
- The new `.claude/rules/*.md` arrive as `new_template_files`; accept them. If your project already had language conventions pasted into CLAUDE.md, delete them there once the rules land, or the same text loads twice.
- **Re-copy `user-level-reference/skills/karpathy-guidelines/SKILL.md` to `~/.claude/skills/karpathy-guidelines/SKILL.md`.** The *Working Preferences* bullets now live in that skill, and coder agents preload it by name from the user-level skills directory. A stale copy means developer agents silently lose the preferences that CLAUDE.md no longer carries — this is the one migration step with a real behavioural consequence.
- If a plugin-installed context-mode routing block is still present in your CLAUDE.md, delete it (removed toolkit-side in PR3).

## v2.0-pr3 — 2026-08-28

**Every agent now declares what it costs.** Transcripts showed the orchestrator on Opus, workers on `sonnet`, Haiku almost unused, and the *built-in* `Explore` inheriting the session model — 219 exploration spawns at Opus prices. In the same window ~400 tool calls hit tools the calling agent did not have (`dotnet-tools`: 87 of 87 failed, advertised in the body and absent from `tools:`), and 5,032 of 10,336 `Read` calls passed no `limit`.

### Model & effort routing

- Every agent file carries `model:` and `effort:`: coders `sonnet` / `medium` / `isolation: worktree`; `tester` + `test-writer` keep their model and gain `effort: medium` + `isolation: worktree`; `architect` + `code-reviewer` `opus` / `high`; `requirements-engineer` + `ops` `sonnet` / `medium`; `doc-generator` `haiku` / `low`.
- **Aliases only** (`sonnet` / `opus` / `haiku` / `fable` / `inherit`) — a model proxy reroutes aliases, and a pinned `claude-*` id bypasses it. Asserted by the verify script.
- `mode: bypassPermissions` is removed from all 61 pre-existing agent files: it is not a documented subagent field and was silently ignored.
- New `## Model & Effort Policy` section in `AGENT_TEAM.md` (×6) with the diagnostic rule: wrong despite full context → bigger model; skipped files or tests not run → raise effort.

### Custom `Explore` agent (new, ×7)

- `.claude/agents/Explore.md` in all 6 variants + `user-level-reference/` overrides the built-in `Explore` and pins it to `haiku`, `effort: low`, `tools: Read, Grep, Glob, Bash`. It carries a breadth contract (`quick` / `medium` / `very thorough`), a 500-line-per-`Read` rule, and a fixed output shape: ranked `path:line — why it matters` plus a ≤5-line synthesis.
- The `model: "haiku"` spawn snippets are gone from `CLAUDE.md` (×6) and the three `AGENT_TEAM.md` spots — the agent file carries the model now, and passing one in the Agent call overrides it.

### Skills actually reachable

- `Skill` added to `tools:` for all 54 agent files that are told to invoke skills. Without it a subagent cannot run the `## Required Skills` block the PO injects — the block had been dead for coders.
- All 12 coders preload `skills: [karpathy-guidelines]`, so the house style is in context from turn one, and all 12 gain `Write`: a coder that cannot create a file is not a coder (44 `Write` calls died on the allowlist in the mined sessions).
- `dotnet-coder` (dotnet, dotnet-maui) gains `mcp__dotnet-tools__build_and_extract_errors` + `mcp__dotnet-tools__run_tests_summary` in `tools:` — the body already told it to use them.

### Native context hooks

- `hooks/read-size-gate.sh` **caps instead of blocking**: an unbounded `Read` whose remaining length exceeds 500 lines is rewritten via `hookSpecificOutput.updatedInput` to carry `limit: 500`, with `additionalContext` naming the next offset. `updatedInput` replaces the whole input object, so `tool_input` is copied wholesale (`pages` and future fields survive). Silent when `limit` is set, the file is short, or the extension is `png|jpg|jpeg|gif|pdf|ipynb`. Fixes the pre-existing bug where `offset` was ignored. The context-mode advice in the old block message is gone.
- `hooks/bash-output-guard.sh` (new, `PostToolUse` on `Bash|PowerShell`, registered unwrapped ×6 + user-level): `tool_response.stdout` **and** `stderr` are checked independently; a stream over 12,000 chars is written whole to `$TMPDIR/claude-bash-out/<session_id>-<epoch>[-stderr].log` and replaced by head 4,000 + a marker naming the log + tail 4,000 via `updatedToolOutput`. Payload shape observed from a real event: `{stdout, stderr, interrupted, isImage, noOutputExpected}`; the sibling fields are copied, not re-invented.
- Both hooks pipe the payload to `node` on **stdin**, never in argv (Linux caps one argument at 128 KiB, Windows CreateProcess caps the command line at 32,767 chars — an argv-passed 200 KB build log would fail to exec and slip through untruncated). `read-size-gate.sh` also runs a single node process per Read instead of five, and decides from `stat` alone above 10 MB rather than scanning the file to count lines.
- `hooks/allow-ctx-plan.sh` deleted. context-mode is an optional plugin from here on, not a routing mandate.

### Verification

- `scripts/verify-template-consistency.sh`: new check **17** (tool-allowlist invariant — every `mcp__server__tool` named in an agent body must be in that agent's `tools:` line; files without `tools:` inherit everything and are exempt) and check **18** (Explore ×7 on haiku, no `claude-*` ids, no `mode:`, `Skill` in all 47 skill-invoking agents, `karpathy-guidelines` preloaded in all 11 coders). Agent count is now 68.
- `scripts/test-hooks.sh`: 101 → 125 fixtures — the Read cap (field-level assertions on `updatedInput`, offset handling, image skip) and the output guard (shape, head/tail, log file, pass-through).

### Downstream migration

1. Run `/sync-template`. `Explore.md` appears as a **new template file** in every variant; accept the agent definitions (`model` / `effort` / `Skill` / `mode:` removal), `AGENT_TEAM.md`, `CLAUDE.md` and `settings.json`.
2. If your `settings.json` is locally modified, add the one new entry by hand: `PostToolUse` matcher `Bash|PowerShell` → `bash hooks/bash-output-guard.sh`, **without** the 127 wrapper. Nothing else in `settings.json` changed.
3. **Delete the plugin-installed `# context-mode — MANDATORY routing rules` block from your project `CLAUDE.md`** if present. The context-mode plugin is optional now; the Read cap and the output guard do the same job natively, without a routing contract the model has to remember.
4. Delete `~/.claude/hooks/allow-ctx-plan.sh` and its matcher group from `~/.claude/settings.json` if you installed it.
5. Do **not** pass `model:` in Agent calls any more — it overrides the agent file's routing silently.

## v2.0-pr2 — 2026-08-28

**Agent teams are retired; parallelism comes from the Agent tool.** Every "sub-agent stalled / went idle without returning" complaint in six weeks of transcripts traced back to a *named teammate*; the 1,777 Agent-tool spawns in the same window never stalled. Agent teams are experimental and off by default, `TeamCreate`/`TeamDelete` no longer exist and `team_name` is deprecated — so the toolkit stops relying on them. What does **not** change: the PO still never does hands-on work at any tier, and `hooks/enforce-delegation.sh` is untouched (it keys on `agent_id`, which Agent-tool subagents provide).

### Retired

- `hooks/require-teammate-report.sh` — the `TeammateIdle` gate becomes a **no-op stub** (header + `exit 0`), removed in v2.1. It stays non-empty so a downstream `settings.json` that still names it does not fail closed on a 127. PR1 already dropped its registration.
- `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` — gone from `user-level-reference/settings.json` and `settings-reference.md`.
- `AGENT_TEAM.md` — the *Agent Naming Convention* section (`dev-1`, `reviewer-2`, …) is deleted: a workstream is a position in the plan, not an agent name. The *Communication Protocol* is now the final-message contract; long tasks use `background: true` and the task-completion notification. The only surviving use of `SendMessage` is asking a *completed* subagent one follow-up question. The stall runbook is rewritten for Agent-tool completions (a foreground call cannot stall — it returns or errors; a background agent is checked once, then treated as failed) and no longer mentions `TaskStop` or `git status` polling. Worktrees are created with `isolation: worktree`, not by hand.
- All 61 agent definitions: the SendMessage progress-ping bullet becomes the final-message contract, and `Team-mode reporting` is renamed `Subagent reporting`. The `## Liveness & Scope` header and the `Scope abort:` clause are unchanged.

### Retro ledger (new)

- `hooks/retro-ledger.sh` (`SubagentStop`, no matcher) parses the finished subagent's own transcript and appends one line per failing run to the project's auto-memory `memory/retro.md`: `date | agent_type | agent_id | dead=[…] | blocks=[…] | errors=n`. A failure is a `tool_result` matching `No such tool available|BLOCKED:|DELEGATE:|CONTRACT VIOLATION|hook error`.
- `hooks/retro-brief.sh` (`SessionStart`, no matcher) prints the last 10 entries; SessionStart stdout is injected as session context, and the Session Bootstrap in every `CLAUDE.md` now has a step that says to fix the cause (agent `tools:` allowlist, prompt, hook) or delegate it before starting new work.
- Both are registered **unwrapped** — no exit-127 fail-closed wrapper. They cannot block anything: every failure path (missing node, missing transcript, unparseable payload, unwritable dir) exits 0. Wrapping a hook that cannot block would only invent a failure mode, exactly as with the other stop-style hooks.
- `scripts/test-hooks.sh`: 71 → 92 fixtures, including a round-trip case (ledger writes, brief reads) that catches the two hooks computing different project slugs — the one way this feature silently does nothing.

### Downstream migration

1. Run `/sync-template` — accept `AGENT_TEAM.md`, the agent definitions, `CLAUDE.md` and `settings.json`.
2. Delete `"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"` from your `~/.claude/settings.json`.
3. **Named-teammate spawns are no longer required.** Use plain Agent calls (several in parallel for parallel workstreams) and read each subagent's final message. If your `settings.json` is locally modified, add the two new entries by hand: `SubagentStop` → `bash hooks/retro-ledger.sh` and `SessionStart` → `bash hooks/retro-brief.sh`, both **without** the 127 wrapper.
4. The retro ledger lands in `~/.claude/projects/<project-slug>/memory/retro.md`, next to `MEMORY.md` — the slug is your project path with every `:` `\` `/` `.` `_` replaced by `-` (`G:\git\foo` → `G--git-foo`). Delete the file to reset the ledger.

## v2.0-pr1 — 2026-08-28

**The git ban is over; the git gates stay.** `hooks/block-bash-vcs.sh` blocked **1,240 turns in 6 weeks** of transcripts to buy nothing — the three git gates keyed on the `mcp__git-tools__*` tool names only because Bash git was banned in the first place. Claude Code 2.1.250 PreToolUse hooks can read `tool_input.command` and deny with exit 2, so the gates now fire on the command itself and the CLI is allowed.

### Hooks

- `hooks/lib/git-cmd.sh` (new) — shared parsing: split the command on `&&`, `||`, `;`, `|` and newlines, unwrap `bash -c "…"` / `sh -lc` / `pwsh -Command` payloads, match **unanchored** per segment (a false positive on `echo "git push origin main"` is the accepted cost of failing closed). `git -C <path>` retargets the repo; `<cwd>/.claude/git-guard-off` is the escape hatch for all three gates.
- `hooks/pre-commit-test.sh` — fires on `git commit` (any `-C` / `-c` prefix, any wrapper). Unchanged behaviour otherwise.
- `hooks/no-push-main.sh` — fires on `git push` to an explicit `main`/`master` ref (including `HEAD:main` and `refs/heads/main`) **or** on a refspec-less push while the checkout is on main. `git push origin feature/x`, `--force-with-lease`, `--tags` and `origin :feature/x` are not blocked.
- `hooks/gate-before-merge.sh` — adds `gh pr merge`, `git merge` while on main, and a push targeting main. The MCP branch for `mcp__MCP_DOCKER__merge_pull_request` / `mcp__github-tools__github_pr_auto_merge` is unchanged (those are GitHub tools, not git-tools). Artifact freshness logic untouched.
- `hooks/block-bash-vcs.sh` — no-op stub for one release, removed in v2.1.
- `scripts/test-hooks.sh` (new) — 46 stdin fixtures over throwaway git repos, including every must-NOT-block case.

### settings.json (all 6 variants + `user-level-reference`)

One `PreToolUse` entry `"Bash|PowerShell"` runs the three gates in order; the `mcp__git-tools__git_commit` / `git_push` entries and the `block-bash-vcs` entry are gone. `Read` gains `hooks/read-size-gate.sh` with a **fail-open** wrapper (127 → exit 0). The `TeammateIdle` block is removed. `permissions.defaultMode` `dontAsk` → `auto`; `Bash(*)`, `WebFetch(*)` and `mcp__git-tools__*` drop out of `allow`, `Bash(bash hooks/run-gate.sh*)` comes in.

### Agents

The `Bash(git *)` / `Bash(gh *)` frontmatter blocks are gone from all 26 coder/tester/test-writer definitions, and the 19 `mcp__git-tools__*` entries leave every coder's `tools:`. The coder merge gate now matches `Bash|mcp__MCP_DOCKER__merge_pull_request|mcp__github-tools__github_pr_auto_merge`, so `gh pr merge` is gated exactly like the MCP tools.

### Downstream migration

1. Run `/sync-template` — it accepts the new `settings.json` and agent definitions.
2. **If your `settings.json` was locally modified**, sync will not rewrite it. Delete the whole `TeammateIdle` block and the `PreToolUse` matcher that invokes `block-bash-vcs.sh` by hand, then add the `"Bash|PowerShell"` entry from `templates/general/.claude/settings.json`. Leaving the old `block-bash-vcs` entry in place is safe but pointless — the script is now a no-op stub.
3. Agents may use the `git` and `gh` CLIs. The **`git-tools` MCP server becomes optional**: nothing in the toolkit requires it, and git work done through it bypasses the gates, which key on `Bash`/`PowerShell` commands.

## v1.5 — 2026-07-29

Closes the item v1.4 recorded as outstanding: `CLAUDE.md`'s *Working Preferences* section restating rules that hooks already enforce.

**18 bullets → 11. 3,939 → 2,393 B per variant.** Always-loaded config on `general`: **34,084 → 32,538 B**, and **41,167 → 32,538 (−20%)** against the pre-trim baseline.

### What was cut, and what enforces it instead

| Bullet | Enforced by |
|---|---|
| Read before editing | the harness — `Edit` fails without a prior `Read` |
| Test after every change | `hooks/pre-commit-test.sh`, `run-gate.sh`, `gate-before-merge.sh` |
| Never push to main | `hooks/no-push-main.sh` (PreToolUse on `git_push`) |
| Read tool discipline | `hooks/read-size-gate.sh` + the routing table in `~/.claude/CLAUDE.md` |
| Subagent discipline | `hooks/enforce-delegation.sh` — the PO cannot edit or build |
| Summarize tool work | no behavioural content |
| Fix CI proactively | no behavioural content beyond "fix the failure" |

In their place, one line naming where the enforcement lives, so the omission reads as deliberate rather than as an oversight. Stating that a mechanism exists, instead of repeating the rule it enforces, is the unhobbling move the Claude 5 context-engineering guidance argues for.

**Kept (11)** — the judgement calls no hook can make: implement-don't-suggest, minimal fix first, analyze before coding, re-plan on failure, tests, post-merge verification, update docs with code, commit messages explain why, clean finish, checkpoint long sessions, learn from corrections. The *Actor note* preamble is kept verbatim: it assigns these to developer agents and is load-bearing for the delegate-everything model.

**Duplication:** the `"22% of total context"` statistic went from **7 files to 1** — the single authoritative copy in `user-level-reference/CLAUDE.md`, which already carries the full Read & Search routing table.

### Why this cut was safe

Nothing under `hooks/` or `scripts/` greps any of this section — verified before editing, not after. That is the opposite of the Superpowers block in v1.4, where two consistency assertions depended on an exact header and a token. Deleting prose a mechanism enforces is safe in a way that deleting an unenforced rule is not.

### Verification

131 assertions green. The section is byte-identical across all six variants before *and* after (single md5), so this was one rewrite applied six times. All seven cut phrases return zero hits across `templates/`. The six enforcing hooks are present and untouched. Section boundaries intact — `general`/`rust-tauri` are followed by `## Quick Start`, the other four by `# Code Style (MANDATORY)`, and the extraction had to stop at any `^#` rather than `^## ` to handle both.

## v1.4 — 2026-07-29

Closes the two items v1.3 left open: the context trim, and a copyable user-level `settings.json`.

### Context trim — measured, and a relocation rather than a deletion

Always-loaded config on the `general` variant: **41,167 B → 34,084 B (−17%)**.

| File | Before | After |
|---|---|---|
| `templates/general/CLAUDE.md` | 17,871 | **15,281** |
| `templates/general/CLAUDE.local.md` | 13,845 | **9,352** |
| user-level `CLAUDE.md` | 8,505 | 8,505 |
| `PROJECT_CONTEXT.md` | 946 | 946 |

Per-variant after: general 34,084 · java 37,254 · python 37,064 · dotnet 38,083 · rust-tauri 39,176 · dotnet-maui 39,861.

Nothing was dropped — three moves, each to a surface that loads on demand:

- **New `mcp-usage` skill** takes ten procedures out of every `CLAUDE.local.md`: Ollama warm-up, large-input digestion, structured extraction, project orientation, code-quality and security sweeps, Context7 lookups, headless batch runs, performance guidance, and the default MCP-first workflow. All ten were present in 6/6 variants and are needed occasionally, so they were pure always-on cost. What stays inline is what binds every turn: registered servers, the git/GitHub MCP-only requirement, Open Brain, trust/verification, failure handling. Skills 11 → 12.
- **Open Brain per-agent tables** (1,750 B of search-query and capture guidance, only relevant while spawning) moved into `AGENT_TEAM.md`, which is already on-demand — appended identically to all six so the §7 byte-identity invariant still holds (47,968 → 49,724 B).
- **Superpowers block** keeps its exact header, its three hard triggers, and a `superpowers:` token, and points at the user-level copy for strong triggers, plugin defaults, and meta skills.

The on-demand side growing while the always-loaded side shrinks is the intended direction, not an accident.

**Guardrail:** `verify-template-consistency.sh` checks 2 and 3 assert the exact `## Superpowers Skills — MUST Invoke Before Responding` header *and* a `superpowers:` token in `CLAUDE.md` and `AGENT_TEAM.md`. Both survived the reduction — verified at 1 exact header and 10 tokens per variant. 131 assertions, all green.

**Still on the list:** `CLAUDE.md`'s 17-bullet *Working Preferences* (~3.9 KB) still restates rules that `no-push-main.sh`, `enforce-delegation.sh`, and the gate now enforce mechanically.

### A copyable user-level `settings.json`

`user-level-reference/` previously shipped only prose. The blocker was whether `~` survives inside a hook `command` string — untested, and a wrong answer would have produced silently dead hooks.

**Measured, not assumed:** a probe bound at both `bash ~/.claude/hooks/…` and `bash $HOME/.claude/hooks/…` fired, and `$0` resolved to the real absolute path in both. So the shipped file uses `~`.

Sanitised: no machine paths (only `CLAUDE_CODE_SHELL`, which is documented as Windows-only), no `statusLine`, no third-party marketplaces or their plugins, no project-specific permission entries. Two permissive settings are called out in the README rather than left for a copier to discover — `Bash(*)` in `permissions.allow`, and the Windows shell path. Two new assertions check the file is valid JSON and that no hook command uses an absolute home path.

## v1.3 — 2026-07-29

Two correctness fixes, both of the same shape: **config that was built correctly and wired to a path nothing reads.**

- **`user-level-reference/` made safe and accurate as a `~/.claude/` source** (#47). Its `coder.md` was a copy of the *template* coder, carrying `PreToolUse` hooks that run `hooks/gate-before-merge.sh` with a `127 → exit 2` fallback. A user-level agent applies in every repo and its frontmatter hooks travel with it: measured, **11 of 20 local repos fall back to user-level agents and 10 have no `hooks/` directory**, so copying it as-is would have made PR merges impossible in 10 repos. Template copies keep the gate; the user-level copy does not; `verify-template-consistency.sh` asserts both halves.
- **Project MCP config now written to `<project-root>/.mcp.json`** (#48) — the only path Claude Code reads for project scope. `dotnet-tools` / `rust-tools` / `windows-mcp` had never loaded in any generated project. Includes a migration warning, an activation check, and a repo-wide correction of the user-scope path to `~/.claude.json`.
- **README documents the toolkit's stance on context engineering for Claude 5 generation models**, with measured numbers on both sides of the ledger: what is already progressive-disclosed (`AGENT_TEAM.md`, 47,968 B, not auto-loaded; 11 on-trigger skills; 13 hooks doing enforcement instead of prose) and what is not yet trimmed (~41 KB always-loaded across 4 files, 11–14 directives/100 lines, known cross-layer duplication).

129 consistency assertions, all green. Detail for each change is in the entries below.

## 2026-07-29 — project MCP servers were written to a path Claude Code never reads

`setup-project.{sh,ps1}` generated `<target>/.claude/.mcp.json`. **Claude Code reads project-scope MCP servers only from `<project-root>/.mcp.json`** — `<project>/.claude/.mcp.json` is an open upstream feature request, not current behaviour (anthropics/claude-code #43296, #3321).

For `dotnet`, `dotnet-maui`, and `rust-tauri` that file was the **sole** registration of `dotnet-tools` / `rust-tools` / `windows-mcp`. Those servers have therefore **never loaded in any project this toolkit set up**. `enableAllProjectMcpServers: true` does not help — it governs auto-approval, not file discovery.

Corroborated locally, independent of the docs: 7 repos keep a working root `.mcp.json`; `InvestmentAdvisor`'s generated `.claude/.mcp.json` (`sqlite`, 2026-02-22) was superseded by a root file (`sqlite, windows-mcp, playwright`, 2026-04-12); in `Yutraffic-Challenge` the `windows-mcp` entry sits only in `.claude/` and is not loaded.

### Changes

- Both setup scripts now write **`<target>/.mcp.json`**, and **never clobber an existing root file** without `--force` (several repos already keep a hand-maintained one) — they print which servers the variant *would* have added instead.
- Both **warn when they find a legacy `.claude/.mcp.json`**, naming it as a path that is not read.
- `scripts/check-activation.sh` gained a *project MCP wiring* section: root file + servers, stale `.claude/` copy, and the exact `mv` to run.
- Root `/.mcp.json` is gitignored in all 6 variants — the generated file carries machine-specific paths (sqlite DB path, `mcp-dev-servers` venv). The legacy line stays so migrating projects don't suddenly start tracking it.
- User-scope path corrected repo-wide to **`~/.claude.json`** (`~/.claude/.mcp.json` is not a concept; an `mcpServers` key in any `settings.json` is silently ignored).
- 12 new consistency assertions pin the write path, the legacy warning, and the gitignore entries (129 checks, all green).

### Migration — required for existing projects

```bash
git mv .claude/.mcp.json .mcp.json     # or merge into an existing root .mcp.json
bash scripts/check-activation.sh .     # confirms wiring
```

### Verification

End-to-end against real setup runs, not just greps: dry-run announces the root path; a real `rust-tauri` run puts `rust-tools, windows-mcp` in root `.mcp.json` as valid JSON with **no** `.claude/.mcp.json`; a pre-existing hand-made root file survives untouched; a planted legacy file triggers the warning.

## 2026-07-29 — v1.2: liveness caps corrected after four days of production exposure

v1.1's two liveness hooks were installed in a real project on 2026-07-25 11:41 and ran for four days. They worked — and both were mis-sized. This release fixes the sizing, adds an audit trail, and adds a way to answer "is it on?" without a transcript investigation.

### What the production data showed

Project `Motorsport-Manager-AI-Agent`, one 208 MB / 10-day transcript. The hooks' own state directories are written on every run, so they are direct proof of execution: the liveness ledger held exactly **3** `.blocked` markers and the budget directory held **150** counter files.

- **The liveness gate exhausted itself in 21 hours.** Its three blocks landed 07-25 18:24, 07-26 13:43 and 07-26 15:49, hitting the session-wide `MAX_BLOCKS=3`. From that point it returned 0 for every subsequent idle — and **618 idle notifications** followed over the next three days.
- **The budget's single block does not stop a runaway.** Across 150 tracked agents: median **15** calls, **35 over 60**, **19 over 120**, worst **417**. Blocking once at 120 and warning thereafter left the 417-call agent running.
- **Neither hook was observable.** Their stderr goes to the agent or teammate, not the lead transcript, and nothing was logged. Grepping the transcript for the hooks' own output returns zero — which is exactly why an initial analysis concluded, wrongly, that the fix had never activated.

### Changes

- **`hooks/require-teammate-report.sh`** — the session-wide `MAX_BLOCKS` cap is **deleted**, not retuned. The per-teammate marker (one block per teammate, ever) is now the only throttle; it already bounds the total at the number of teammates that qualify. An intermediate design added a daily cap and was cut: the measured worst day is 10, so it could never bind.
- **`hooks/agent-budget-warn.sh`** — blocks now **escalate**: 120, 180, 240, and every 60 thereafter, instead of blocking once. Every threshold test is `-eq`, never `-ge`, so calls between thresholds pass and a blocked agent can still deliver its partial report.
- **Audit trail** — both hooks append to `.claude/liveness.log` (gitignored in every variant). **Threshold events only**: the budget hook runs on every tool call, so logging passes would add a second hot-path write and ~10,000 lines of no signal per session. Writes are best-effort and can never change an exit code.
- **`scripts/check-activation.sh`** (new) — reports, for any project: hook bindings in `settings.json`, hook scripts on disk, kill switches, `.claude/liveness.log` contents, and the ledger directories that prove execution.

### Measured effect

Replayed the **shipped** script over the same 208 MB transcript, feeding each of the 250 qualifying triggers the transcript prefix it would have seen in production:

| | blocks | worst day |
|---|---|---|
| v1.1 (`MAX_BLOCKS=3`) | **3** | — |
| v1.2 (no session cap) | **41** | 10 |

That is the whole claim. It does not say teammates now report reliably — it says the gate stays armed for the life of a long session instead of 21 hours.

### Rollout — required, and not automatic

**A template is a source, not a shipment.** v1.1 was merged to `templates/` and reached exactly **one of 15** projects; the rest have no `TeammateIdle` binding and mostly no `hooks/` directory, so for them the fix has never existed. Getting v1.2 into a project needs both halves:

1. the scripts in `<project>/hooks/`, and
2. the bindings in `<project>/.claude/settings.json`.

`/sync-template` installs both. Verify with `bash scripts/check-activation.sh <path-to-project>`. These hooks are deliberately **not** registered at user level: their commands are `bash hooks/…`, resolved relative to the project root.

### Verification

21 hook assertions plus the replay gate, all passing. Notable cases: a 4th distinct teammate blocks (v1.1's cap suppressed it) and 10 more after that; a teammate that reported is never blocked (guards the escape-tolerant regex against JSON-escaped tags); calls 121–179 all pass between block thresholds; the budget log contains exactly 4 lines after 250 calls, not 250.

## 2026-07-25 — Agent liveness, part 2: TeammateIdle report gate + tool-call budget

Part 2 binds the two hooks part 1 deferred, after verifying every mechanism against live hook stdin rather than documentation. **Also corrects a number reported in part 1.**

### Correction to part 1

Part 1 claimed "64 of 90 teammates never sent a substantive message." **That figure was wrong — the true count is 4 of 90.** The mining pass that produced it only parsed `message.content` when it was a string, so it missed every teammate message delivered as array-form content. Re-measured over the full transcript: 90 teammates, 279 bare idle notifications, **305** substantive messages, and 86 of 90 teammates reported at least once.

The pain point is real but has a different shape than reported. It is not "teammates never report" — it is **teammates idling repeatedly between reports**. Worst observed run: `m13-coder` with the sequence `R R I I I I I I I I I I R …` — ten consecutive idles with no output. That reframing changed the trigger: a "never reported" gate would have fired for 4 of 90 teammates and been useless.

### Verified hook contracts (measured, not documented)

A log-only probe captured real stdin for every candidate event:

- **`TeammateIdle`** carries `teammate_name`, `team_name`, `session_id`, `transcript_path` (the **lead's** transcript, where teammate messages land), `cwd`, `prompt_id`, `permission_mode`. `exit 2` **blocks the idle**, and the stderr text is delivered **to the teammate** — confirmed end-to-end: a probe teammate read the block message and converted its silent idle into a report. It has **no loop guard**; it fired twice for the same teammate 9 s apart, so a hook here must carry its own ledger.
- **`PreToolUse` fires for named teammates and carries `agent_id` plus `agent_type`.** This was the open question that gated the budget hook: teammates are separate sessions, and `agent_id` is documented as subagent-only. It is present, so the agents that actually run away are reachable.
- **`Stop`** carries `last_assistant_message` and `background_tasks`, but `background_tasks` reported `status: "running"` for a teammate that had idled 12 s earlier and carries no `teammate_name` — useless for idle detection. **`TaskCompleted`** carries no `teammate_name` and no task result, so it cannot attribute a completion to a teammate or judge report substance.
- Hook config **hot-reloads**; the "read at session start" note added in part 1 was wrong and is corrected here.
- `"*"` is not a match-all matcher (malformed regex); omitting `matcher` is. Per-hook `if` filters work, verified firing exactly once on a narrow pattern.

### New hooks

- **`hooks/require-teammate-report.sh`** (`TeammateIdle`, **not** 127-wrapped — a missing stop-style gate must never trap teammates in a loop). Blocks when a teammate has **2 recorded unreported idles**, i.e. this is at least its second idle with no report in between — the point at which the existing Escalation Protocol runbook says to act. On the measured transcript that selects 14 of 90 teammates; a threshold of 1 would have selected 84 of 90 and fired on healthy report-then-idle cycles. Append-only ledger keyed `session_id` + `teammate_name` (never deleted — deleting on a second idle, the pattern `enforce-agent-contract.sh` safely uses for a once-per-agent `SubagentStop`, would loop block→pass→block forever here), one block per teammate, max 3 per session, `.claude/liveness-off` kill switch, fail-open on every unexpected condition. A teammate absent from the transcript fails open: absence of evidence is not evidence of silence.
- **`hooks/agent-budget-warn.sh`** (`PreToolUse`, no matcher, WARN-on-127 wrapper). Advisory WARN at 60 tool calls, blocks **once** at 120, then warns every 60. Not a hard wall — the goal is one deliberate reconsideration, since a wall would break legitimate large tasks. Pure-shell hot path (one `grep`, no `node`) and an immediate `exit 0` on the main thread, because it runs on every agent tool call. Counters are per-`agent_id` under a per-session directory.

### Verification

32 assertions across two suites, all passing: trigger thresholds (report-then-one-idle does not block; two idles do; a report resets the streak), ledger non-deletion across repeated idles, per-session cap, fail-open paths (missing/malformed/absent), budget thresholds and per-agent counter isolation, and the kill switch. Both hooks were then replayed against the real 167-hour transcript and agreed with hand-verified ground truth on every teammate tested; whole-file scan of 68 MB costs ~0.6 s and only runs on a teammate idle.

Two bugs were caught by testing and are worth recording. The report detector originally required bare `"` in the message tags, but transcript tags are JSON-encoded (`from=\"name\"`), so every reporting teammate read as silent — the patterns are now escape-tolerant. And an apostrophe inside the `node -e` script terminated its single-quoted shell string, making bash parse the JavaScript and exit 2 on every call, which masqueraded as the gate working.

### Downstream migration
- Re-run `/sync-template`, then **restart the session** (or rely on hot-reload) so the two new hook bindings load. `settings.json` changes in all 6 variants: one `TeammateIdle` entry and one matcher-less `PreToolUse` entry.
- Both hooks fail open and both honour `.claude/liveness-off` if you need them off.
- Tune `IDLE_STREAK_BEFORE_BLOCK`, `MAX_BLOCKS`, `WARN_AT`, and `BLOCK_AT` at the top of each script.

## 2026-07-25 — Agent liveness & right-sizing, part 1: prose contracts + hook-event reference

Session-mining round 6, from a 167-hour Motorsport-Manager-AI-Agent transcript (18,237 lines, 107 user turns). Two reported pain points — sub-agents going stale without reporting, and long phases for small issues — were measured rather than assumed, and the measurement contradicted the obvious fix.

**What the data showed.** There are two agent populations and only one fails. `Agent`-tool sub-agents: **35 of 35 completed and reported**, with every `<result>` payload ≥1,606 chars (median 8,371) and zero stall-like finals — the notification carries the report inline, so a sub-agent that stops properly reports automatically. Named teammates (separate sessions, `teammate-message` protocol): **64 of 90 never sent a substantive message**, against 145 bare idle notifications and 43 real ones. Widening the `SubagentStop` contract matcher — the intuitive fix — was therefore dropped: it targets a population with a 0% failure rate. Separately, 22 of 107 turns spawned more than 2 agents (6 agents for a read-only question, 5 for `"continue"`), and the worst single spawn ran 565 tool calls over 4.2 hours against a median of 38.

**Landing in this part (prose + docs only — no behavior-gating hooks yet):**
- All **61 agent definitions** (53 template across 6 variants + 8 `user-level-reference/`) gain a `## Liveness & Scope (HARD REQUIREMENT)` block: a progress-ping cadence (one line via SendMessage roughly every 20 tool calls, so silence is distinguishable from work) and a **scope-abort** clause — if the task grows past its stated scope, stop and report partial + blocker rather than expanding inside one spawn. The scope-abort clause targets the runaway spawns directly.
- `AGENT_TEAM.md` (all 6, md5-identical): right-sizing rules in *Tier Selection Guidelines* — lowest defensible tier wins, the tier table is a **cap** on team size rather than a menu, single file/symbol ⇒ T1, question-shaped turns spawn at most one agent, and never spawn `Explore` for a file that is already named. Three new *T1 Examples* rows drawn from the mined incidents. Both spawn-prompt snippets (report agents **and** coders) now carry the ping + scope-abort lines.
- `CLAUDE.md` (all 6): team-size-is-a-maximum note under the tier table.
- `user-level-reference/settings-reference.md`: **corrected a wrong claim** that `SubagentStop` is informational — it blocks with exit 2, which is exactly what `hooks/enforce-agent-contract.sh` depends on. Added the agent-team lifecycle events (`Stop`, `TeammateIdle`, `TaskCreated`, `TaskCompleted`, `SubagentStart`), the full authoritative event enum, `async`/`asyncRewake`, the note that **`"*"` is malformed regex and not a match-all matcher** (omit `matcher` instead), and that hook config is only read at session start.
- `commands/sprint.md`: treat missing pings, not elapsed time, as the stall signal.

**Deliberately deferred to part 2**, because the mechanism must be verified before it is shipped: `TeammateIdle` and `TaskCompleted` are documented, blockable, and bound by nothing in this toolkit — that is where the 64 silent teammates are reachable. A probe is staged locally to capture their real stdin before any gate is written. Note also that the 64-teammate figure proves silence on the *message channel only*; MMAA's work did land on `main`, so any future gate must trigger on "no report **and** no completed task", never on "no report" alone.

### Downstream migration
- Re-run `/sync-template`. Agent definitions, `AGENT_TEAM.md`, and `CLAUDE.md` change in all 6 variants; all changes are additive prose — no hook or settings changes in this part, so nothing needs a restart.
- No new hooks and no `settings.json` changes, so the §13 hook-ref invariant and existing gate behavior are untouched.

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
