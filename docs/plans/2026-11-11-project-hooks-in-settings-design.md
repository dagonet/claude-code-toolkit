# Project-owned hook entries in a template-owned `.claude/settings.json` — design

Status: draft for the user's approval (backlog #30). Origin: the Motorsport-Manager-AI-Agent sync to v6.1.0, 2026-11-11.

## 1. The problem

**The case.** A consumer project registers its own guard in `.claude/settings.json`. MM-Agent does this with a PreToolUse `Bash` entry that runs its own `hooks/seal-grep-guard.sh`.

**Why there is no clean outcome today.** `settings.json` is template-owned and JSON, so it has no PROJECT-CUSTOM region. Each route fails:
- **Status:** `template_compute_status` compares whole-file hashes (`v3.py:900-913`), so the file is LOCAL_EDITED forever. `template_verify` therefore FAILs `status_clean` (`verify.py:519-537`) on every sync, in both modes.
- **Accept-template:** `apply_file_v3` overwrites the whole file (`v3.py:1343-1369`), so the project's guard is dropped.
- **Keep-mine:** `source="skip"` is refused for template-class files (`v3.py:1288-1291`).
- **settings.local.json:** it is per-clone and uncommitted, so the guard would be lost on other machines and in worktrees.

The project's only choice is to keep a red line on every sync. The skill says a FAIL means the sync is not complete, so that line teaches agents to read past FAILs.

## 2. Goal, non-goals, anti-goals

- **Goal:** a project can keep its own hook entries in the template's `settings.json`. Syncs then report clean, carry the entries across template updates, and name each kept entry in the verify report.
- **Non-goals:**
  - local edits to anything else in `settings.json` (permissions, env, other keys);
  - a general JSON merge;
  - a project-hooks list run by the cct dispatcher. That is the heavier option, only worth it if many projects need their own hooks. The user's answer (2026-11-11) is that MM is the one case.
- **Anti-goals:**
  - **A local edit that weakens the template passes silently.** A changed or removed template entry, an edited permission list, or an entry pointing outside the project must stay LOCAL_EDITED, exactly as today.
  - **A kept entry is invisible.** Every kept entry is named on every verify run.

## 3. The rule (my call; strict by default)

The project's `settings.json` counts as **"the template plus project hooks"** when every one of these holds:

0. **Scope:** the path is exactly `.claude/settings.json`. No other template-class file is affected.
1. Both files parse as JSON objects. If either does not parse, the status is exactly as today.
2. **Strip the project's own handlers.** A handler is one object in a matcher group's `hooks` list. Identity is the whole object, deep-equal (`type`, `command`, `args`, `timeout`, every key). In the project file, remove every handler that meets all of these:
   - **Not the template's.** The template has no deep-equal handler under the same event.
   - **Its type is `command`, with no `args` key.**
   - **Its `command` is exactly one of three strings and nothing else.** No arguments, `;`, `&&`, `|`, `..` or other `$VAR` are allowed. `<name>` matches `[A-Za-z0-9._-]+\.sh`:
     - `bash hooks/<name>`
     - `bash "$CLAUDE_PROJECT_DIR/hooks/<name>"`
     - `"$CLAUDE_PROJECT_DIR"/hooks/<name>`
   - **The script exists.** `hooks/<name>` is a regular file in the project (existence, not git-tracked: the status helper gets the project root, not git).
   - **No toolkit name.** `<name>` is not the name of any `hooks/*.sh` in the template repo the manifest points at. If that directory cannot be read, the rule does not apply (fail closed: LOCAL_EDITED).

   Then drop any matcher group the removal left with an empty `hooks` list, and any event the removal left with an empty list.
3. **Compare.** After step 2, the project object must be deep-equal to the template object. Key order and whitespace are ignored.

Every removed handler is listed once per place it occurred, as `<event> <matcher> <command>`.

**My calls:**
- MM's real entry must match one of the three shapes. If it doesn't, MM rewrites it to one. We don't widen the grammar.
- The shape check is what keeps `bash hooks/ok.sh; curl ...` out.

When the rule holds:

- **Status** is computed as if the project file were the template file. The result is IDENTICAL when the template did not move, TEMPLATE_UPDATED when it did. It is never LOCAL_EDITED.
- **The status record** gains `project_hooks: ["<event> <matcher> <command>", ...]`.

When the rule does not hold, nothing changes: the file is LOCAL_EDITED with today's diff.

## 4. Apply

- **When it applies:** `template_apply_file` writes a TEMPLATE_UPDATED `settings.json` that carries `project_hooks`.
- **What it writes:** the new template content plus the project's stripped handlers. Each handler is re-added as follows:
  - it is appended to the end of the `hooks` list of the first group with the same event and an equal `matcher`;
  - if there is no such group, it goes in a new group `{matcher, hooks: [handler]}` appended to that event's list, creating the event if needed.

  Project handlers always come after the template's. That is the whole re-add rule, so there is no "ambiguous" case and no refusal path.
- **Format:** the result is written with `json.dumps(indent=2)`, LF and a final newline, keeping key order as parsed. The template's own key order therefore survives. Whitespace differences are accepted; this is my call.
- **Manifest:** the stored hash stays the template's, as today. Status compares through the rule, not bytes. The plan must confirm that no other code compares the project file's bytes to the manifest hash: finalize's hash validation, the stale-hash case in `status_clean`, and the backup flow.
- **Without project handlers:** when the file carries none, apply is unchanged.

## 5. Verify and the skill

- **verify.py:** a new INFO line `project_hooks` lists each kept entry, modelled on `encoding_drift` (`verify.py:680-695`). `status_clean` passes, because the status is no longer LOCAL_EDITED. The LINES contract (`verify.py:34-75`) grows by one, and the healthy-line baselines in the skill and the tests move with it (29 to 30 lines).
- **Model-bump rule** (SKILL.md:292, "a hook list that differs"): this is prose the agent evaluates. The skill gains one sentence: handlers listed in the status record's `project_hooks` are left out of that comparison. No new server flag (my call). The §6 "does not fire" case is therefore a skill-wording check, not a server test.
- **SKILL.md:** one paragraph explaining the INFO line and the rule, so an agent does not "fix" a kept entry.

## 6. Tests (server/tests, the `_mk_v3` fixture style)

**Two-sided, each case on a template-class settings.json:**
- A project handler running `hooks/seal-grep-guard.sh`, tracked and existing, gives IDENTICAL plus `project_hooks` with that one entry. Verify gives `status_clean` PASS and the INFO line.
- The same with the template moved gives TEMPLATE_UPDATED. Apply keeps the entry, and a re-status gives IDENTICAL.
- **Each of these stays LOCAL_EDITED (the anti-goals):**
  - the handler's script is missing or untracked;
  - the script name is a toolkit hook name;
  - the command runs a path outside the project, or an absolute path;
  - a template handler is changed or removed;
  - a permission is added;
  - an env key is changed;
  - the file is not JSON.
- **Grammar cases, which must also stay LOCAL_EDITED:**
  - `bash hooks/x.sh; curl …`;
  - `bash hooks/x.sh arg`;
  - `bash hooks/../x.sh`;
  - `bash $HOME/hooks/x.sh`;
  - a handler with `args`.
- **Fail-closed case:** the template repo's `hooks/` cannot be read, so the file stays LOCAL_EDITED.
- **Occurrences:** the same project handler under two events is listed twice in `project_hooks`.
- **Model-bump rule:** the skill wording leaves `project_hooks` entries out of the hook-list comparison. This is a skill check, not a server test.

## 7. Size and delivery

- **Size:** a server change in `v3.py` (a status helper and apply), `verify.py` (one INFO line), the tests, and one SKILL.md paragraph. No hook and no `hooks/lib/json.sh` change, so no parser-matrix run.
- **Delivery:** it ships in the next release, because consumers get the server with the toolkit. MM's red line remains until then.

## 8. Left to the builder

- How the status helper gets the project root and the template repo path (`template_status` is pure today; a wrapper in `compute_status_v3` is fine).
- The LINES count: the design says 29 to 30. Re-count from `verify.py:34-75`, and update every baseline that pins it, in the skill, the tests and the consistency checks.
