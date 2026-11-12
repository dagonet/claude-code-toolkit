# Project-owned hook entries in settings.json — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A consumer's `.claude/settings.json` that is "the template plus the project's own hook handlers" reads clean in status and verify. Its handlers survive template updates, and each is named by a new INFO line.

**Architecture:**
- A pure helper module `server/src/template_sync/project_hooks.py` holds three pieces:
  - the command grammar;
  - the strip operation, which takes the project's own handlers out;
  - the re-add operation.
- `v3.compute_status_v3` and `v3.apply_file_v3` call it only for `.claude/settings.json`. They do so after the existing `region_status` second opinion, the same pattern.
- `verify.py` gains one INFO id, `project_hooks`.

**Tech Stack:** Python 3 (stdlib `json`, `re`, `pathlib`), pytest, under the server venv.

**Spec:** `docs/plans/2026-11-11-project-hooks-in-settings-design.md` (approved 2026-11-11, dashboard #8).

## Global Constraints

- **Scope:** exactly the project path `.claude/settings.json`. Every other file behaves byte-for-byte as today.
- **Command grammar:** the handler has `"type": "command"`, no `args` key, and a `command` that full-matches one of these three. `<name>` is `[A-Za-z0-9._-]+\.sh`.
  - `bash hooks/<name>`
  - `bash "$CLAUDE_PROJECT_DIR/hooks/<name>"`
  - `"$CLAUDE_PROJECT_DIR"/hooks/<name>`
- **Script check:** `<pp>/hooks/<name>` is a regular file and not a symlink.
- **Name check:** `<name>` (compared lowercase) is not among the names of `<template repo root>/hooks/*.sh`. If that directory cannot be listed, the rule does not apply.
- **Handler identity:** the whole handler dict, deep-equal. A handler is "the template's" when the template has a deep-equal handler under the same event, in any matcher group.
- **Comparison:** after stripping the project's handlers and dropping emptied groups and events, the project object must be deep-equal (`==` on parsed JSON) to the current template object, or else to the base template object (`resolve_base`).
- **Status:** IDENTICAL or TEMPLATE_UPDATED by the existing hash rule (`core._sha256(tpl_replaced) != entry_hash`). Never LOCAL_EDITED when the rule holds.
- **Labels:** `project_hooks` holds one string per removed occurrence: `f"{event} {matcher!s} {command}"`, where `matcher` is the group's `matcher` value or `None`.
- **Apply format:** `json.dumps(obj, indent=2, ensure_ascii=False) + "\n"`, with LF. The manifest hash stays `core._sha256(tpl_replaced)`, unchanged.
- **Re-add:** append the handler to the `hooks` list of the first group under the same event with an equal `matcher`. Otherwise append a new group `{"matcher": m, "hooks": [h]}` (omit `matcher` when it was absent), creating the event list if needed.
- **Text rules:** KISS. LF everywhere. Never print environment variable values.
- **Tests:** `server/.venv/bin/python -m pytest <file> -q` from the repo root. The full gate is `bash hooks/run-gate.sh`; it is machine-wide, so announce it.

## Review Focus

1. **Near-miss commands must stay LOCAL_EDITED** (Task 1, test `test_grammar_rejects_near_misses`): double spaces, a trailing argument, `;`, `&&`, `|`, `..`, `$HOME/`, an absolute path, and a handler with `args`.
2. **A symlinked `hooks/x.sh` must stay LOCAL_EDITED, even when its target is inside the project** (Task 1, `test_symlink_script_is_not_project_owned`).
3. **A project name equal to a toolkit hook in different case must stay LOCAL_EDITED** (Task 1, `test_toolkit_name_case_insensitive`). Windows file systems are case-insensitive.
4. **A CRLF or BOM project `settings.json` must behave like the LF one** (Task 1, `test_crlf_and_bom_project_file`). Parse the content `read_with_flags` returns, and strip a leading U+FEFF before `json.loads`.
5. **A real local edit plus a project handler must stay LOCAL_EDITED, and apply must back up as today** (Task 2, `test_apply_mixed_edit_keeps_old_path`). An example of a real local edit is an added permission.

---

### Task 1: The rule and status

**Files:**
- Create: `server/src/template_sync/project_hooks.py`
- Modify: `server/src/template_sync/v3.py`, the LOCAL_EDITED branch of `compute_status_v3` (around :1181-1193, right after `region_status`)
- Test: `server/tests/test_template_sync_project_hooks.py` (new; reuse `_mk_v3`, `_tpl_entry` and `_status` by importing them from `test_template_sync_v3_status`)

**Interfaces:**
- Produces these definitions in `project_hooks.py`:
  - `SETTINGS_PATH = ".claude/settings.json"`
  - `COMMAND_RE`: the compiled full-match regex for the three shapes. Group `name` captures `<name>`.
  - `toolkit_hook_names(repo_root: pathlib.Path) -> frozenset[str] | None`: lowercase names of `repo_root/"hooks"/*.sh`, or `None` if the directory cannot be listed.
  - `strip_project_hooks(proj: dict, tpl: dict, pp: pathlib.Path, names: frozenset[str]) -> tuple[dict, list[tuple[str, object, dict]]]`: returns a deep copy of `proj` with the project's handlers removed and emptied groups and events dropped, plus the removed `(event, matcher, handler)` triples in file order.
  - `labels(removed) -> list[str]`: builds the label strings defined in Global Constraints.
  - `project_hooks_status(entry_hash_hex: str, tpl_replaced: str | None, proj_content: str | None, pp: pathlib.Path, names: frozenset[str] | None, base_provider) -> tuple[str, list[tuple[str, object, dict]]] | None`. It returns `None` (leave the verdict alone) when any of these holds:
    - either side is `None` or is not a JSON object;
    - `names is None`;
    - nothing was removed;
    - the stripped project equals neither the template nor the base.

    Otherwise it returns `(status, removed)`. `base_provider` is called only when the stripped project differs from the current template.
- Produces in `compute_status_v3`: a status entry for `.claude/settings.json` that gains `"project_hooks": [labels]` and loses `local_diff` and `local_diff_kind` when the rule holds.

- [ ] **Step 1: Write the failing tests** in `test_template_sync_project_hooks.py`. Use template `TPL` = `{"permissions": {"allow": ["Read"]}, "hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "bash hooks/no-push-main.sh"}]}]}}`. The toolkit repo gets `hooks/no-push-main.sh`, and the project gets `hooks/seal-grep-guard.sh`. Use project handler `H = {"type": "command", "command": "bash hooks/seal-grep-guard.sh"}`.
  - `test_project_handler_reads_identical`: the project is TPL with `H` appended to the Bash group. The status is `IDENTICAL`, `project_hooks == ["PreToolUse Bash bash hooks/seal-grep-guard.sh"]`, `"local_diff" not in info`, and `summary["local_edited"] == 0`.
  - `test_project_handler_new_group_reads_identical`: `H` sits in its own group with `"matcher": "Edit"`. Status `IDENTICAL`.
  - `test_template_moved_reads_template_updated`: the template file changes (a permission is added), the manifest hash stays the old TPL's, and the project is old TPL plus `H`. Status `TEMPLATE_UPDATED`, with `project_hooks` present (this is the base path).
  - `test_grammar_rejects_near_misses`: parametrized over the commands in Review Focus 1, each with a matching file where one is needed. Status `LOCAL_EDITED`, and `"project_hooks" not in info`.
  - `test_missing_script_stays_local_edited`
  - `test_symlink_script_is_not_project_owned`
  - `test_toolkit_name_case_insensitive`: the project script is `hooks/No-Push-Main.sh`.
  - `test_template_handler_changed_stays_local_edited`: the template's handler command is altered in the project.
  - `test_permission_added_stays_local_edited`: `H` plus an extra `allow` entry.
  - `test_unreadable_toolkit_hooks_dir_fails_closed`: the toolkit repo has no `hooks/`. Status `LOCAL_EDITED`.
  - `test_not_json_stays_local_edited`
  - `test_two_events_listed_twice`: `H` under both PreToolUse and PostToolUse gives 2 labels.
  - `test_crlf_and_bom_project_file`
  - `test_other_paths_untouched`: a template-class `CLAUDE.md` edit is still `LOCAL_EDITED` with `local_diff_kind`.

- [ ] **Step 2: Run them and see them fail.** Run `server/.venv/bin/python -m pytest server/tests/test_template_sync_project_hooks.py -q`. Expected: an import error or failures. The `*_stays_local_edited` cases may pass already. At least the four positive cases must fail.

- [ ] **Step 3: Implement `project_hooks.py`** to the interfaces above.
  - Wire it in `compute_status_v3`. When `proj_rel == SETTINGS_PATH` and the status is still `LOCAL_EDITED` after `region_status`, call `project_hooks_status(entry_hash, tpl_replaced, proj_content, pp, toolkit_hook_names(repo_root), lambda: resolve_base(pp, manifest, rules, tpl_rel)[0])`.
  - On a non-`None` result, set `status` and `local_diff = None`, and set `info["project_hooks"] = labels(removed)`.
  - Compute `toolkit_hook_names` once per `compute_status_v3` call, lazily, only when the settings path needs it.

- [ ] **Step 4: Run them and see them pass.** Run the same command, plus `server/.venv/bin/python -m pytest server/tests/test_template_sync_v3_status.py server/tests/test_template_sync_v3_region.py -q`. Expected: all pass.

- [ ] **Step 5: Commit** `feat(sync): a settings.json that is the template plus project-owned hook handlers is not LOCAL_EDITED (#30)`.

### Task 2: Apply carries the handlers across

**Files:**
- Modify: `server/src/template_sync/project_hooks.py` (add `readd`), and `server/src/template_sync/v3.py` `apply_file_v3`, template class with `source == "template"` (around :1340-1369)
- Test: `server/tests/test_template_sync_project_hooks.py`

**Interfaces:**
- Consumes `project_hooks_status`, `toolkit_hook_names` and `SETTINGS_PATH` from Task 1.
- Produces `readd(tpl_obj: dict, removed: list[tuple[str, object, dict]]) -> dict`, following the Global Constraints re-add rule. It returns a new dict and does not mutate `tpl_obj`.
- `apply_file_v3`: when `proj_rel == SETTINGS_PATH`, `source == "template"`, and `project_hooks_status(...)` is not `None` for `proj_existing`:
  - `write_content = json.dumps(readd(json.loads(tpl_replaced), removed), indent=2, ensure_ascii=False) + "\n"`;
  - `local_edit = False`;
  - no backup is taken;
  - the result gains `"project_hooks": labels(removed)`.

- [ ] **Step 1: Write the failing tests.**
  - `test_apply_keeps_project_handler`: the template moved, and the project is old TPL plus `H`. After `template_apply_file(source="template")`, the file parses to the new template plus `H` in the Bash group. `backup is None` and `local_edit_overwritten is False`. The manifest-entry hash equals `sha256(new template)`. A fresh `template_compute_status` reads `IDENTICAL` with `project_hooks`.
  - `test_apply_matcher_gone_appends_group`: the new template has no Bash group. `H` lands in a new `{"matcher": "Bash", ...}` group at the end of PreToolUse.
  - `test_apply_mixed_edit_keeps_old_path`: the project is `H` plus an added permission. Apply without `backup_dir` returns today's LOCAL_EDITED error. With `backup_dir`, it backs up and overwrites, so `H` is gone and the backup holds it.
  - `test_apply_without_project_handlers_unchanged`: a plain TEMPLATE_UPDATED settings.json is written byte-equal to the template, as today.

- [ ] **Step 2: Run them and see them fail.** Same command. The first two fail.

- [ ] **Step 3: Implement** `readd` and the `apply_file_v3` branch. Put the branch before `splice_region`'s result is used for this path. Every other path is untouched.

- [ ] **Step 4: Run them and see them pass,** together with `server/tests/test_template_sync_v3_apply.py` and `server/tests/test_template_sync_settings_hooks.py`.

- [ ] **Step 5: Commit** `feat(sync): template apply keeps a project's own hook handlers in settings.json (#30)`.

### Task 3: The verify line, the skill and the docs

**Files:**
- Modify:
  - `server/src/template_sync/verify.py`: `LINES` (:36-75), and the INFO block after `project_md_scoped_consistent`'s emission;
  - `server/tests/test_template_sync_verify.py`: :380 (`== 29`), :1363, and the fixtures' `info_ids` sets;
  - `skills/sync-template/SKILL.md`: :285-293 (the model-bump rule), :1176-1182 (the `info_ids` table), :1380-1382 (the healthy lines and `LINES = 29`);
  - `docs/template-sync.md`: the pinned line counts.
- Test: `server/tests/test_template_sync_verify.py`

**Interfaces:**
- Consumes `info["project_hooks"]` from Task 1.
- Produces the verify id `project_hooks` (INFO_LINE), inserted into `LINES` immediately before `("tree_clean", FAIL_LINE)`. `len(verify.LINES) == 30`.

- [ ] **Step 1: Write the failing tests.**
  - `test_project_hooks_info_line`: a project with `H` gives `status_clean` PASS, and a `project_hooks` INFO line whose measured text contains `.claude/settings.json: PreToolUse Bash bash hooks/seal-grep-guard.sh`.
  - `test_project_hooks_info_line_none`: with no project handlers, the measured text is `no project-owned hook handlers`.
  - Update :380 to `== 30`, and :1363 to `== 30`.
  - In every healthy-summary fixture, `project_hooks` is in `info_ids`, so INFO goes from 8 to 9 and from 9 to 10.

- [ ] **Step 2: Run** `server/.venv/bin/python -m pytest server/tests/test_template_sync_verify.py -q`. Expected: FAIL.

- [ ] **Step 3: Implement the line,** modelled on `encoding_drift` (:680-695):
  - with a status error: INFO `cannot compute -- <error>`;
  - otherwise: INFO with `"; ".join(f"{p}: {l}" for p, info in files for l in info.get("project_hooks", []))`, or the none text.
  - The expected text in both cases is `"n/a (informational)"`.

- [ ] **Step 4: Update the skill and the docs.**
  - **SKILL.md:292**, append: "Handlers listed in the status record's `project_hooks` are the project's own (see step 8's `project_hooks` INFO line) and are left out of this comparison."
  - **The `info_ids` table:** add `project_hooks`.
  - **:1380-1382:** each healthy line gets INFO +1. They become `20 PASS, 0 FAIL, 1 SKIP, 9 INFO`, `21 PASS, 0 FAIL, 0 SKIP, 9 INFO` and `20 PASS, 0 FAIL, 0 SKIP, 10 INFO`, and `LINES = 30`. The older-server note becomes `LINES = 33`, read `PASS = 33 - …`. Check whether that older-server note is still accurate, and leave it alone if it describes pre-v5 servers.
  - **One new paragraph in step 8:** what the `project_hooks` line means, and "do not remove a listed handler to make it go away".
  - **`docs/template-sync.md`:** the same count changes.

- [ ] **Step 5: Run** `server/.venv/bin/python -m pytest server/tests/test_template_sync_verify.py -q`, then `bash scripts/test-server.sh`. Expected: all pass.

- [ ] **Step 6: Commit** `feat(sync): verify reports project-owned settings.json hook handlers as INFO; skill + docs (#30)`.

### Final verification (controller)

- [ ] `bash scripts/verify-template-consistency.sh`: ALL CHECKS PASSED.
- [ ] Gate: `bash hooks/run-gate.sh`, announced and foreground. Expected `GATE PASS`.
- [ ] No parser-matrix run: no hook and no `hooks/lib/json.sh` changes.
- [ ] Whole-branch review on the most capable model. Focus on the anti-goals (spec §2), the grammar, and fail-closed.
- [ ] PR via MCP; the user merges. The CHANGELOG entry and version bump come with the next release.
- [ ] **MM check before the release:** ask the PC helper for MM's exact registration string. If it is not one of the three shapes, MM rewrites it at its next sync (spec §3, my call).
