---
name: sync-template
description: Pull template updates into the current project. Triggers on /sync-template.
disable-model-invocation: true
---

# Sync Template (Downstream)

Pull updates from the claude-code-toolkit template repo into the current project.

**Requires:** `template-sync-tools` MCP server registered and running.

## Workflow

### 1. Load Manifest

Call `template_load_manifest(project_path=".")`.

- If `valid` is false, stop and show the errors to the user.
- If `warnings` mentions v1 migration, inform the user their manifest will be upgraded to v2.

### 2. Compute Status

Call `template_compute_status(project_path=".")`.

Show the summary to the user:
```
Sync Status: {variant} @ {template_commit} (last synced: {last_synced_commit})

  Auto-update:  {summary.auto_update} files (template changed, project unchanged)
  Conflicts:    {summary.conflict} files (both changed — needs review)
  Up to date:   {summary.up_to_date} files
  Project-only: {summary.project_custom} files
  New files:    {len(new_template_files)} available
  Deleted:      {summary.template_deleted} warnings
```

If everything is up-to-date and no new files, report "Already in sync" and finalize.

**Model-bump surfacing:** tell the user BEFORE applying anything — "This bump changes the operating model — review the CHANGELOG's Downstream-migration notes in the template repo first" — when ANY of these appear in the auto-update or conflict set:

- `CLAUDE.md`, `CLAUDE.local.md`, or `AGENT_TEAM.md` (an operating-model change can live in the MCP rules file, not just CLAUDE.md);
- `.claude/settings.json` whose hook list differs from the project's (a hook added, removed, or re-matched IS the enforcement layer changing);
- any `TEMPLATE_DELETED` file under `hooks/` — a deleted hook is always an enforcement change.

### 3. Auto-Update Files

For each file with status `AUTO_UPDATE`:

Call `template_apply_file(project_path=".", file_path=F, source="template")`.

**Apply in this order — it is not cosmetic.** `settings.json` takes effect in memory the moment it is written (hooks hot-reload), so writing it before the scripts it names leaves the new matchers pointing at the old scripts: a consumer that applied the v2 `settings.json` first got the v2 `Bash|PowerShell` matcher running the v1 `gate-before-merge.sh` on *every* Bash call and was fail-closed on `ls` for the rest of the session.

1. `hooks/lib/**` — sourced libs first; a script whose lib is missing defines no helpers.
2. `hooks/*.sh` — the scripts themselves.
3. `.claude/agents/*` — agent frontmatter `hooks:` can reference the scripts.
4. `.claude/rules/*`
5. `.claude/settings.json` — last of the enforcement wiring, so every script it names already exists in its new form.
6. everything else (`CLAUDE.md`, `AGENT_TEAM.md`, docs, …).

The same order applies to the CONFLICT resolutions in step 4 and the new files in step 5: never write `settings.json` before the hooks it wires. If `hooks/` is missing or partial at the project root, run step 6b's restore BEFORE writing `.claude/settings.json` — the order above is useless if the scripts it protects were never materialised.

**Smoke test immediately after the `.claude/settings.json` write**: run a harmless `Bash(true)`. If it is blocked, the recovery note in the "Restart the session" area above applies — apply `hooks/lib/git-cmd.sh` and the three gates via `template_apply_file` (no shell needed) rather than continuing the sync through a fail-closed session.

**Any hook probe must live in a script file run via `bash <path>`, never inline.** The gates scan the whole command STRING by design, not just what a git subcommand would actually do — an inline compound command that merely *mentions* `git push origin main` (in a comment, an echo, a string literal) trips the gate it is trying to test. The result is then uninterpretable: a block does not tell you whether the gate works or whether your own probe was the violation it caught. Write the probe to a temp file and run `bash <path>` instead.

**Positive control — prove the gates are LIVE, not merely unblocked.** `Bash(true)` succeeding only proves nothing blocked it; a fully inert enforcement layer passes that test too. Write this to `"${TMPDIR:-/tmp}/gate-probe.sh"` (or somewhere under `.claude/`) and run it with `bash "$TMPDIR/gate-probe.sh"`. **Do not** write it to a repo-relative path like `probe.sh` — `enforce-delegation.sh` denies main-thread writes outside the PO write surface, so the probe never gets created.

```sh
printf '{"tool_name":"Bash","tool_input":{"command":"git push origin main"},"cwd":"<repo>"}' \
  | bash "${CLAUDE_PROJECT_DIR:-.}/hooks/no-push-main.sh"
echo "exit=$?"
```

Use **forward slashes** in the JSON `cwd` (`C:/git/foo`, not `C:\git\foo`): a Windows backslash is a JSON escape and the payload will not parse, which the hook treats as unreadable and passes — a false green on the very check you are running.

Expect `exit=2` and a `BLOCKED` line on stderr. **`exit=0` means the gates are inert** — the scripts are missing, empty, or not wired — and the sync is running unprotected: apply `hooks/lib/git-cmd.sh` and the three gate scripts via `template_apply_file` (the recovery note below), then re-run the probe before continuing.

> **Recovery — if every Bash call is blocked mid-sync:** apply `hooks/lib/git-cmd.sh` and then the three gate scripts (`pre-commit-test.sh`, `no-push-main.sh`, `gate-before-merge.sh`) via `template_apply_file`, which needs no shell. Do **not** restart the session first — the half-applied state persists on disk, and a restart only re-reads the same broken combination. Once Bash works again, finish the sync in the order above and restart per the final report.

Collect all results. Report the list of auto-updated files.

### 4. Resolve Conflicts

For each file with status `CONFLICT`:

1. Call `template_get_diff(project_path=".", file_path=F, diff_type="three_way")`
2. **Disqualify the unsafe options BEFORE offering anything.** Both of these are checks on the diff you just fetched:
   - *Accept merged* is off the table unless `auto_merged` survives inspection: diff it against BOTH `template_content` and `project_content` for lines present in base AND project; if any are missing, do not offer it — a clean merge is not a correct merge. For `hooks/*.sh`, also `bash -n` the merged body (and `node --check` any embedded `node -e` block); a syntax error is a conflict, not a clean merge.
   - *Accept template* is off the table when it would silently drop project content: an EMPTY `PROJECT-CUSTOM` region while headings the template does not carry sit outside it (list those headings), or — for `.claude/settings.json` — a `matcher` string naming agents the template version no longer mentions, e.g. a project-added `cpp-coder` (list those agent names; accept-template reverts their hook wiring). In either case route to the splice path (`source="provided"`) instead.
3. Present what is left:
   - If `has_conflicts` is **false** and `auto_merged` passed step 2: show it and offer to apply.
   - Otherwise show the conflict markers and the `unified_diff`, and ask the user how to resolve, offering only the options step 2 did not disqualify:
     - **Accept merged** (if they edit the merged content)
     - **Accept template** (discard local changes)
     - **Keep mine** (acknowledge template change but keep project version)
     - **Splice** (`source="provided"` with hand-merged content)
4. Apply the user's choice:
   - Accept merged/template: `template_apply_file(source="provided", content=...)` or `template_apply_file(source="template")`
   - Keep mine: `template_apply_file(source="skip")`

> **PROJECT-CUSTOM region:** the server preserves content between `<!-- PROJECT-CUSTOM:BEGIN -->` and `<!-- PROJECT-CUSTOM:END -->` mechanically (when both template and project carry the markers). If the consumer's `template-sync-tools` server predates region support, preserve the project's region verbatim in any manual `CLAUDE.md` merge — never let accept-template clobber it.
>
> Since v2.1.2 the markers also ship at the end of every `.claude/agents/*.md` and of `AGENT_TEAM.md` — the region split is file-agnostic, so those files now merge exactly like `CLAUDE.md`. On the first sync that brings the markers in, **move the project's existing custom agent lines into the region once**; anything left above the BEGIN marker is template territory and the next accept-template will overwrite it.
>
> "EMPTY region" in the accept-template disqualifier above means *no content other than the shipped `<!-- Project-specific rules, routing blocks, and extensions go here. -->` placeholder* — the placeholder alone does not make a region non-empty.

### 5. Handle New Files

For each file in `new_template_files`:

Ask the user whether to add it. If yes:

Call `template_apply_file(project_path=".", file_path=F, source="template")`.

**Duplicate-load warning:** for a new `.claude/rules/*.md`, grep `CLAUDE.md` for each of its headings. A heading present in both means the project pasted that section into `CLAUDE.md` before the template extracted it into a path-scoped rule — it would now load twice. List the duplicated headings and offer to delete the `CLAUDE.md` copy.

### 6. Handle Template-Deleted Files

For each file with status `TEMPLATE_DELETED`:

1. Determine whether anything still references it: run the same reference grep as step 6b (`.claude/settings.json` plus the `hooks:` frontmatter of every `.claude/agents/*.md`).
2. Report the state precisely:
   - "preserved **and unreferenced — safe to delete**" — the new `settings.json` and agents no longer mention it;
   - "preserved **and still referenced by `<file>`**" — deleting it would take enforcement offline.
3. ASK the user. Recommend accepting the deletion in the unreferenced case; delete with `git rm <file>` so the removal is in the diff. Never delete on your own initiative, and never delete a project-owned file the template never shipped. (`git rm` here, and `git add`/`git commit` in step 9, are the PO's documented git-I/O role for this skill per `AGENT_TEAM.md` — not hands-on coding.)
   - **Ordering:** delete a template-removed hook only AFTER the new `.claude/settings.json` has been applied (step 3's order) AND the step-6b reference grep — re-run against that new `settings.json` — shows it unreferenced. Deleting it while the in-memory settings still wire it makes every matching tool call exit 127 and fail closed for the rest of the session.
4. For a deleted **hook**, cross-reference the user-level copy: the dangerous twin usually lives at `~/.claude/hooks/<name>.sh`, which no project sync touches. Tell the user to remove it there too (see the CHANGELOG's downstream-migration notes).

### 6b. Verify Hook Scripts (MANDATORY)

Hooks fail OPEN when their script is missing (exit 127 → the tool call proceeds with only a non-blocking error). A synced project with a populated `.claude/settings.json` but an empty `hooks/` directory runs with its entire enforcement layer silently absent — this happened in production.

> Read the toolkit working tree with Read/Grep, never through the context-mode sandbox: `git -C` fails silently on its `/tmp` paths and `grep -c` comes back 0, so every verification below would report a false clean.

1. Collect every `hooks/<name>.sh` reference on a `command:` line in `.claude/settings.json` AND in the `hooks:` frontmatter of every file in `.claude/agents/`. Match **both** invocation forms: the legacy cwd-relative `bash hooks/<name>.sh` and the v2.1.2 `bash "$CLAUDE_PROJECT_DIR/hooks/<name>.sh"`. Anchoring on `command:` keeps the `Bash(bash hooks/run-gate.sh*)` permissions pattern out of the set — it is a prompt rule, not a hook.
1b. Collect the **sourced libs** too — a hook that cannot source its lib defines no helpers, reads an empty command, and exits 0 on everything. In every hook script present at the project root, grep for `\. "\$\(dirname "\$0"\)/lib/[^"]+"` and for a plain `lib/git-cmd.sh`; add each `hooks/lib/<file>` to the referenced set. They are checked and restored exactly like the scripts in steps 2–4 (`source="template"` when missing — the server resolves the `hooks/lib/` subdirectory against the toolkit root).
2. For each referenced script: verify `hooks/<name>.sh` exists at the project repo root and is non-empty.
3. For any MISSING script: call `template_apply_file(project_path=".", file_path="hooks/<name>.sh", source="template")` — the server resolves root-tracked `hooks/` paths against the toolkit ROOT (variants do NOT ship `hooks/` — never look in `templates/<variant>/hooks/`, it does not exist) and both materializes the file AND returns its manifest entry in one call. Never hand-copy. Add each result to the collected `applied_files`.
4. For every referenced hook script PRESENT at the project root, NOT tracked in the manifest, AND NOT already applied by step 3 (the two sets are disjoint): call `template_apply_file(project_path=".", file_path="hooks/<name>.sh", source="skip")` and add the result to `applied_files`. `source="skip"` registers a manifest entry from the project's existing file content WITHOUT writing — NEVER use `source="template"` here, it would silently overwrite locally-edited hook scripts. Once registered, future `template_compute_status` runs track hook drift like any other file.
5. Report the verified list: `Hooks verified: N referenced, N present (M restored, K registered in manifest)`.

### 7. Finalize

Call `template_finalize_sync(project_path=".", applied_files=<JSON array of all template_apply_file results>)`.

Build `applied_files` PROGRAMMATICALLY from the collected `template_apply_file` results only — never hand-assemble or re-type entries (hand-typed hashes have silently corrupted a manifest; the server now rejects malformed hashes, but the discipline stands).

**Post-finalize self-check:** re-run `template_compute_status(project_path=".")`. A clean sync shows `auto_update: 0, conflict: 0`. Anything else means the manifest was corrupted during finalize — report it to the user instead of finishing.

### 8. Report

Then run `bash <toolkit>/scripts/verify-user-level-drift.sh` and fold its result into the report as one line.

Re-run the step-3 **positive control** here as well (the same temp script, `bash <path>`) and fold its result in: the sync rewrote `hooks/` and `settings.json` since the first probe, so this is the run that tells you the *post-sync* enforcement layer is live. `exit=2` + `BLOCKED` → report `Gates: live`. `exit=0` → report `Gates: INERT` and the recovery note, not a clean sync.

The FIRST line of the report is this sentence, verbatim:

```
Gates are live immediately (settings.json hot-reloads). Restart before relying on changed agent definitions or skills.

Sync complete: {variant} @ {new_commit}

  Auto-updated: [list]
  Merged:       [list]
  Skipped:      [list]
  New files:    [list]
  Warnings:     [list]
  User-level:   [one-line verify-user-level-drift.sh summary]
```

### 9. Commit the Sync

Commit the synced tree yourself, from the main thread — `git add`/`git commit` here are the PO's documented git-I/O role for this skill, not hands-on coding (`AGENT_TEAM.md`: agents without a usable tree return work; the PO commits). **Never spawn a worktree-isolated agent to commit a sync.** `coder`, `*-coder`, `tester`, and `test-writer` all set `isolation: worktree`; the harness creates that worktree from `main`, whose `hooks/` predate the sync, while the session's hot-reloaded `settings.json` already fires the v2 gates on every Bash call — the result is every Bash call in that worktree blocked ("BLOCKED: Tests failed…" even for `ls`). If you must delegate this step, use `ops` or `general-purpose` (neither sets `isolation: worktree`).

Before `git add`/`git commit`: run `git diff CLAUDE.md` and check for a re-appended `# context-mode — MANDATORY routing rules` block. The context-mode plugin re-appends this block after `PROJECT-CUSTOM:END` on every session start, so a CLAUDE.md cleaned earlier in the sync is dirty again by the time you commit. Remove the re-appended block (or disable the plugin) before staging, otherwise the commit silently reintroduces it.

Match the plugin's **heading**, not the phrase: `grep -c '^# context-mode' CLAUDE.md` must be `0`. The template's own text mentions "context-mode" by design (the sentinel section under `## context-mode plugin`), so a substring grep reports a false positive on a perfectly clean file; only a line *starting* `# context-mode` is the re-appended plugin block.

Stage exactly the sync's touched files — the list is already in hand: every `applied_files` result from step 7, plus any files `git rm`'d in step 6. `git add -- <paths>`, then `git commit`. Never `git add -A`: it sweeps up untracked run artifacts (scratch scripts, `.gate/`, stray output files) that were never part of the sync.

**The full sequence under v2.1.3+ hooks — the order is load-bearing:**

```sh
git add -- <applied_files from step 7> <git-rm'd paths from step 6> .claude/template-manifest.json
git commit -m "chore: sync template to <commit>"   # PreToolUse: with **Test** present this
                                                   # runs the tests only and writes NO artifact
# --> now delegate ONE `bash hooks/run-gate.sh` run to `ops` (the PO cannot run the gate)
git push -u origin <branch>
gh pr create --fill
gh pr merge --squash --delete-branch
git fetch -p                                       # drops the phantom remote-tracking ref
```

Gate **after** the commit, never before: the artifact must match the PR head by sha or tree. A gate run before the commit reports "artifact stale" at merge time unless the tree is byte-identical either side of the commit.

**The commit gate keys on the WORKING TREE at gate time — commit exactly what was gated.** A chained `git add … && git commit` is fine (the tree the gate hashed is the tree the commit gets); so is `git commit -a`. A *partial* add after the gate ran mismatches by design — the committed tree is not what was gated — and the merge gate will correctly demand a fresh run.

CI fires on `pull_request` and on push-to-main; a bare branch push produces **no** run. Open the PR first, then look up the run id — an empty workflow list right after `git push` is not a CI failure.

## Rules

- NEVER auto-update a `CONFLICT` file without user confirmation
- NEVER delete a project-owned file the template never shipped. A `TEMPLATE_DELETED` file is different: ask, and delete it with `git rm` when the user accepts (step 6)
- NEVER apply an `auto_merged` body without checking it for dropped lines — and, for a hook, without a `bash -n`
- NEVER finalize without the hook-script verification (step 6b), sourced libs included — a missing script or lib fails open and silently disables enforcement
- NEVER register PRESENT hooks with `source="template"` in step 6b — `source="skip"` for present-but-untracked (registration must not overwrite local edits); `source="template"` is ONLY for scripts missing from disk (step 3)
- NEVER hand-assemble or re-type `applied_files` entries — collect the tool results verbatim
- ALWAYS re-run `template_compute_status` after finalize and report anything other than a clean result
- ALWAYS call `template_finalize_sync` at the end, even if no files changed (updates `lastSynced`)
- All hashing, diffing, and placeholder replacement is handled by the MCP tools — do NOT compute hashes or apply placeholders manually
