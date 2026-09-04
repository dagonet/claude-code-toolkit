---
name: sync-template
description: Pull template updates into the current project. Triggers on /sync-template.
disable-model-invocation: true
---

<!-- SYNC-TEMPLATE-SKILL-VERSION: v3.0.3 -->

# Sync Template (Downstream)

Pull updates from the claude-code-toolkit template repo into the current project.

**The line above is the version of the body YOU LOADED, and you must be able to state it.** A running session obeys the skill body it read at session start, not the file on disk — measured live: an installed `SKILL.md` byte-identical to the current release while sessions started earlier were still executing the previous version's steps. So *"re-copy `SKILL.md`"* and *"the drift check reports 0"* can both pass while every live session runs the old workflow. Step 1 checks this marker against the installed file.

**Requires:** `template-sync-tools` MCP server registered and running, **version >= 0.2.0**.

> The two repos keep **independent** semver and ship on different cadences — do not expect the numbers to match. They are related by this stated contract instead. `template-sync-tools` 0.1.0 carries a classification bug that silently OVERWRITES a file the user chose to keep; 0.2.0 is the first release with the fix. Check the version at the first `template_*` call and stop if it is older.
>
> The fix lives in the SERVER PROCESS, so a consumer on a remote box must **pull, then restart** — a restart alone re-launches the same old code. One breaking field change a caller could key on: `locally_modified` now means "deviates from the template" (it used to mean "changed since the last sync"; that meaning moved to a new `changed_since_sync` field).

## Workflow

### 1. Load Manifest

**FIRST, assert your own body against the installed file (v2.2.5 round 4).** Before any `template_*` call:

```
grep -m1 'SYNC-TEMPLATE-SKILL-VERSION' ~/.claude/skills/sync-template/SKILL.md
```

Compare that to the marker at the top of *this text as you loaded it*, and **state both in the report** (`SKILL body:` line, step 8). If they differ, **STOP**: you are running a stale body against a newer manifest and your steps are not the shipped ones. The remedy is a **session RESTART** — re-copying the file does nothing for a session that has already read it.

**The honest limit, and it is the important half: this marker cannot rescue a session already at risk.** A session running an *older* body has no assertion in it to fire and can never self-detect — it will simply not perform this check. The marker prevents the **next** occurrence, not the current one. If a stale run is suspected and this check is absent from what you loaded, that absence *is* the answer.

Then call `template_load_manifest(project_path=".")`.

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

### 2b. Back Up the GITIGNORED Tracked Files (MANDATORY, before any write)

**Every other file this sync touches is recoverable; these are not.** A wrong `template_apply_file` on a tracked file is a `git checkout --` away, and it shows up in the PR diff before anyone merges it. A file that is BOTH manifest-tracked AND gitignored has no history, no diff, and no undo — an erroneous overwrite is simply gone.

`CLAUDE.local.md` is the file this describes in every variant: gitignored by the shipped `.gitignore`, tracked by the manifest, and deviating **by design** in any project that customised its MCP rules. Back it up first and by name.

Derive the set rather than assuming it is only that one — a project may gitignore more. **Use exactly this invocation; the "obvious" implementation of the previous wording backed up nothing and reported success on two different repos.**

**Keep the script you build from this step ASCII-ONLY, or set `PYTHONIOENCODING=utf-8` before running it.** Windows Python's default stdout is cp1252: one non-ASCII character in a `print` — a set-intersection sign copied out of this page, an em dash in a status line — raises `UnicodeEncodeError` **before the copy runs**, and the step then reports nothing at all. A crash before the backup is precisely the failure this step exists to prevent. Measured on a consumer sync: U+2229 in a progress print, backup not written on the first attempt.

```
# Method 1 — one process, NUL-separated BYTES. `-z` is not optional.
git check-ignore -z --stdin        # stdin: b"\0".join(paths); every hit is unrecoverable

# Method 2 — one process per path, works everywhere, instant for a few dozen paths.
git check-ignore -v -- <path>      # a hit prints `.gitignore:<line>:<pattern>\t<path>`
```

**Why `-z`, stated so it is not re-derived wrongly.** Written from Python in text mode on Windows, `"CLAUDE.local.md\n"` reaches git as `CLAUDE.local.md\r`. Without `-z`, `check-ignore --stdin` splits on `\n`, so it tests a path ending in `\r`, which matches no rule. It then exits **1 — meaning "none of these paths are ignored", which is indistinguishable from a genuine clean result — and prints nothing to stderr.** The same pipe typed in Git Bash works, because the shell writes bare `\n`; it fails specifically under the script-driven invocation this step actually uses. Measured:

| written as | result |
|---|---|
| text mode, `'CLAUDE.local.md\n'` | rc=1, empty — **silently "nothing ignored"** |
| bytes, `b'CLAUDE.local.md\n'` | rc=0, HIT |
| bytes, `b'CLAUDE.local.md\r\n'` | rc=1, empty — the `\r` is the cause |
| bytes, `-z`, `b'CLAUDE.local.md\0'` | rc=0, HIT |

**The same `\r` hazard applies to how you OBTAIN the path list, one layer earlier than the table above** (v2.2.4, consumer feedback): write it with `sys.stdout.buffer`, or assert the list is CR-free before using it. **Method 2 is the MORE exposed of the two**, despite being presented as the works-everywhere alternative, because its path source is left to the implementer — Method 1 escapes only because it builds bytes inside Python (`b"\0".join`) and never round-trips through text mode. A consumer's `python3 -c 'print(...)' | mapfile -t` produced `CLAUDE.local.md\r` for all 36 paths, and `check-ignore -q` then returned 1 for every one of them. Their cross-check is what caught it. The guard, verbatim:

```
for p in "${PATHS[@]}"; do case "$p" in *$'\r') echo "FATAL: CR in path [$p]"; exit 1;; esac; done
```

**Two assertions, both required before the result is trusted:**

1. **Cross-check the methods.** Run both and assert they return the same set; print `both methods agree` before copying anything. `git status --porcelain --ignored` (which lists `!! <path>`) is a third, independent confirmation if they disagree.
2. **Assert non-empty when the manifest tracks `CLAUDE.local.md`** — every variant ships it and every shipped `.gitignore` ignores it, so an empty set there is impossible and means the check failed, not that there is nothing to protect. **This assertion is the one that does not depend on getting the invocation right**, which is why it exists: it catches the whole class, including the next variant of it. An empty set with `CLAUDE.local.md` in the manifest stops the sync; it does not proceed with `Backup: <dir> []`.

**What each of those two can and cannot tell you (v2.2.5, and it matters when one of them fires).** The cross-check is what actually caught the `\r` defect above: one method disagreed with two others, and the disagreement *localised* the fault to path hygiene. The non-empty assertion is the opposite instrument — it would have fired on the same defect and told the consumer only that the set was empty, sending them hunting a manifest bug that did not exist. **It tells you SOMETHING is wrong, not WHAT.** Keep both: assertion 1 diagnoses, assertion 2 is the last line and survives the case assertion 1 cannot reach — both arms of the cross-check call `git check-ignore`, so they share an implementation and can be wrong *together*. Four syncs and assertion 2 has never fired; that is what an invariant is supposed to do, not evidence it is dead weight.

**Control for assertion 2, because an untested last line is indistinguishable from an absent one.** Before trusting the result, plant a temp path that is definitely gitignored (append a unique name to `.gitignore`, create the file) and a temp path that is definitely NOT, run the same derivation over both, and assert the ignored one comes back and the plain one does not. **Both arms are required**: a positive-only control passes just as happily against a derivation that returns *every* path, which is a live failure mode here (a superset fallback is explicitly allowed further down this step), not a hypothetical one. Remove the two temp paths afterwards. One temp file each, deterministic, and it converts "this assertion has never fired" into "this assertion still works".

**Back up a SECOND set as well: `new_template_files` INTERSECT exists-on-disk (v2.2.5).** The set above is manifest-scoped, and invariant I1's data-loss class is defined by *not* being in the manifest — so the first set structurally cannot cover it, and a gitignored member of it has no history, no diff and no undo. Adding it here is the only mechanism on the table that reaches that case.

> **Do NOT reorder this step to make that work.** `new_template_files` is already in hand: this step runs AFTER step 2 (Compute Status), despite what its label suggests — "2b" reads as belonging to step 2's *inputs* when it is sequenced after step 2's *output*. Moving a step whose entire contract is *before any write* is exactly how the next data-loss bug gets introduced, and here it would buy nothing.

**ADOPTION INTO AN EXISTING REPOSITORY is the worst case, and it is not a corner (corrected in v2.2.6 — the previous wording named `bootstrap`, which is the one population NOT exposed).** Adoption is a hand-written or minimal manifest pointed at a tree that is already full of pre-existing files: **every one of them is simultaneously present-on-disk and absent-from-manifest** — the whole destructive intersection at once, on the path where the manifest-scoped backup protects nothing whatsoever. It runs `/sync-template`, so this step executes, and it is very likely where the 156-line project gate in invariant I1 was actually lost: an existing repo with content, not a fresh tree. The second set above is the only thing standing between adoption and the work already in the tree.

> **Why the old wording had to go, stated so it is not re-imported.** It said *"a fresh bootstrap has an empty manifest, so every hand-written file is simultaneously present-on-disk and absent-from-manifest"*. Both halves are false, verified on **both** bootstrap paths: `setup-project.sh` generates the manifest itself and writes a populated `files{}` entry per copied file, and `setup-project.ps1` mirrors it (`templateHash` / `templateRawHash`). So (1) bootstrap does not produce an empty manifest — tree and manifest are consistent the moment it finishes, on Windows as well as POSIX; and (2) bootstrap does not run this skill at all, it is a separate script, so this step never executes on that path. A reader reasoned *"bootstrap means `setup-project.sh`, which I am not running, therefore this paragraph is not about me"* — **and they were right. The warning named the one population that is not exposed**, which is how it got dismissed by exactly the people who need it. Same guard, same second backup set, correct audience.

**`new_template_files` being empty is STRUCTURAL for a mature repo, not a sampling accident** — it means *absent from the MANIFEST*, and a repo that has synced before has every template file tracked. It is non-empty in exactly two situations: the template ADDS a file, or the manifest does not yet describe the tree (adoption, above). Four consecutive consumer syncs reported it empty, so **an empty second set is the expected reading, not evidence that this step ran.** Say which it was in the report.

**Back up a THIRD set: everything ON DISK in every directory a destructive operation TOUCHES (v2.4.0, item A3).**

Concretely: for every `TEMPLATE_DELETED` path, back up **every file in that path's directory that exists on disk** — not just the deleted path, and **not only the manifest-tracked ones**. Deletion is the only irreversible-by-design operation in this skill, and a region-bearing agent file is in **neither** of the two sets above: it is not gitignored-and-tracked, and it is not a new template file. Git recovers a tracked one, so that alone is not catastrophic — but it also changes the step-6 prompt qualitatively: *"safe to delete (backed up at `<path>`)"* is a materially different question from *"safe to delete"*.

> **⚠ SCOPE THIS BY WHAT IS ON DISK IN THE TOUCHED DIRECTORY, NOT BY MANIFEST MEMBERSHIP** — and the reason reads as over-caution until you know what it protects.
>
> A consumer has `.claude/agents/game-tester.md`: **project-owned, not manifest-tracked** (ten agent files tracked, that one not). So it is **not `TEMPLATE_DELETED`, not `new_template_files`, and not covered by this step's manifest-scoped sets on any path.** A consolidation that rewrites `.claude/agents/` wholesale meets it **with no backup anywhere.** That is invariant I1's class one directory over.
>
> Git settles what that file actually is: hand-authored through its own PR, extended in a second, still in use three months later, `tools:` listing 18 project-specific MCP tools that exist only in that repo's own harness, and a description encoding a domain policy of theirs. **Toolkit files matching `*game-tester*` across all branches and all history: zero.**
>
> **Every other file in that `.claude/agents/` can be restored from the template. That one exists only there.**
>
> **Manifest membership tracks TEMPLATE PROVENANCE, not importance** — and a consolidation naturally runs on the opposite intuition, that the untracked file is the leftover. It is the inverse: **the untracked file is the only one nobody can regenerate.** Scoping by what is on disk in the touched directory is what makes provenance stop deciding survival.

**Consumers customise in two styles, and only one is visible to a manifest-scoped guard.** *Editing* a tracked file surfaces as `CONFLICT`, is covered by the manifest-scoped backup, and is recoverable from git besides. *Adding* an untracked file is invisible to classification **by construction**. Editing is safe because the manifest knows the path; adding is unsafe because nothing does.

**A census of who currently holds orphans measures which style is popular, not how bad the failure is** — and the failure is unrecoverable file loss, no backup on any path, no prompt, in a directory a consolidation rewrites wholesale. A second consumer measured **zero** orphans (25 files on disk across `.claude/agents/`, `.claude/rules/` and `hooks/`, all 25 manifest-tracked, both directions clean across the whole 34-entry manifest). **Do not read that as "one of two, therefore marginal."** On a repo that only ever edits tracked files the manifest is bidirectionally consistent and *is* a trustworthy authority — nine syncs with no drift in either direction. **That is a property of that repo, not of manifests**, and it is not the case this set is written for. On such a repo the guard copies nothing extra and costs nothing, which is what a clean repo should look like.

Copy each hit from ALL THREE sets to a `template-sync-backup-<timestamp>/` directory under the temp root, preserving relative paths, and **report the ABSOLUTE, RESOLVED path** so the user can find it without asking. Do not delete it at the end of the sync — step 5's post-apply guard reads it.

> **⚠ `/tmp` IS DRIVE-RELATIVE ON WINDOWS, AND THIS STEP RUNS FROM PYTHON.** `${TMPDIR:-/tmp}` is a *shell* idiom; one layer over, in Python with `TMPDIR` unset, `os.path.abspath('/tmp/template-sync-backup-…')` resolves against the **current drive** and yields `G:\tmp\…`, which is not MSYS `/tmp`. **The copy succeeds — only the reported path is wrong**, which is the worst shape it could take: a consumer ran their own `diff` against the path they were given and it failed.
>
> This step's entire contract is *"name the backup directory so the user can find it without asking"*, on the one step whose job is protecting **unrecoverable** files. A user told `/tmp/...`, who looks there and finds nothing, concludes **the backup did not happen**.
>
> **So: derive the temp root explicitly, and print the resolved absolute path.**
>
> ```python
> import os, tempfile
> root = os.environ.get("TMPDIR") or tempfile.gettempdir()   # never a bare "/tmp"
> backup = os.path.realpath(os.path.join(root, f"template-sync-backup-{stamp}"))
> ```
>
> `os.path.realpath`, not `abspath` — it resolves symlinks and the `/tmp` → real-directory mapping as well as making the path absolute. Print `backup` verbatim in the report; do **not** re-print the `${TMPDIR:-/tmp}` expression you wrote in the source.
>
> **Same class as the `\r`-in-`check-ignore` defect above and the `which`-resolved `bash -n` in step 4: a shell idiom means something different one layer over.** All three fail without an error, and all three are caught by printing the thing that was actually used rather than the expression that produced it.

> **Report the third set separately from the first two**, and name the directories it was derived from. A count folded into the others hides whether it ran at all — and unlike `new_template_files`, an empty third set is *not* the expected reading: it means no `TEMPLATE_DELETED` path had a directory, which on a sync that deletes anything is a derivation failure, not a clean result.

**If Bash commands starting with `git` are BLOCKED in this project, both methods above are unexecutable** (pre-v2.1 configs shipped a `block-bash-vcs.sh`; this toolkit removed it in v2.1, so this reaches only consumers still on such a config). The step anticipates a false clean, not a hard block. Two git-free routes, in preference order: use the server's `template_list_gitignored` when the installed `template-sync-tools` has it — the real fix, and the same one this step already names; otherwise parse `.gitignore` yourself and, where that is ambiguous, **back up the manifest's whole path list as a superset**. A superset backup is cheap and always correct — over-copying costs disk, under-copying costs the file. What is NOT acceptable is skipping 2b because the check would not run: that is a 127 being read as a verdict.

> The server is the only layer that can see both facts at once (it holds the manifest and can read `.gitignore`), so a server-side refusal is the real fix and is filed upstream. This step is the client-side guard until it lands.

### Apply-time invariants — these OUTRANK the step numbering (v2.2.5)

The steps below are numbered for reading order, not for precedence. Three rules apply to **every** write in steps 3, 4, 5 and 6b, whichever list the path arrived in. All three exist because the numbering was followed literally and destroyed work, or hid it.

Two general rules govern how they, and every guard in this file, are written. Neither is decoration — each was earned by a specific failure in this release:

> **A guard must be keyed on the DECISION that was made, not on the list the file arrived in.** A list describes *provenance*; a guard enforces *intent*. Enforcing intent off a provenance list is what miscategorises the legitimate case, and the fix for that false positive is always to weaken the guard.

> **A guard that cannot be observed firing is indistinguishable from one that was deleted — so every guard against an invisible failure ships with a CONTROL that makes it visible.** A comment defends a guard against a reader; it does not defend it against a refactor, a merge, or a tidy-up six months out. A control converts *"this looks redundant"* into *"deleting this turns something red"*. Verify each control **by deleting its guard**: if the control still passes, it is decorative and tests the surrounding machinery instead. And a control SET needs both arms — positives alone cannot distinguish a working guard from one that fires on everything.

**I1 — a file that EXISTS in the project is never written from the template without an explicit conflict resolution, whatever list it appeared in.** `new_template_files` means *absent from the MANIFEST*, not *absent from the PROJECT*: `template_compute_status` decides that list by manifest membership alone and never looks at the disk. A path that is present on disk, untracked in the manifest, and also shipped by the template therefore appears in `new_template_files` while step 6b rule 4 says — correctly — that it must be registered `source="skip"`. Step 5 runs first, so following the numbering lets the destructive reading win. It has: a consumer lost a 156-line project-specific gate this way, and **step 2b cannot cover it**, because 2b backs up *manifest-tracked* paths and this file's defining property is that it is not one. The reporter recovered only because the file happened to be git-tracked; a gitignored one would simply be gone. The user cannot save themselves either — they are asked "add this new file?" about a file that already exists with their content in it, and "yes" is the reasonable answer to the question as posed.

**I2 — `.claude/settings.json` is written only after every script it references exists on disk**, regardless of which step introduced those scripts. **State this as a PRECONDITION, not as an ordering rule, and check it where the write happens:** immediately before writing `settings.json`, verify every `hooks/` path it references exists and is non-empty; refuse the write otherwise. An ordering rule silently degrades the next time a step is inserted or renumbered — which is precisely how this bug arose — while a precondition checked at the point of the write does not. Step 3's order (libs → hooks → agents → rules → settings.json → everything else) is the same order for the conflict resolutions in step 4 and the new files in step 5 — and new files arrive *later in the numbering* than the settings.json write, which is the trap: on one reported sync **9 of 11 new files were hooks/libs that the auto-updated `settings.json` wires**, so the literal step order would have installed a `settings.json` naming nine scripts that did not yet exist (every matching tool call exits 127 and fails closed). Adopt new libs and hooks BEFORE writing `settings.json`, then agents, then `settings.json`, then docs — regardless of step number.

**I3 — when the `TEMPLATE_DELETED` set is NON-EMPTY, no write in steps 3, 4, 5 or 6b happens until the step-6d BASELINE sweep has been captured for every deleted agent name.** 6d reports a **delta** (`5 -> 0`), and a delta needs a *before*. There is only one moment a before can be taken: while the tree still holds the references the sync is about to rewrite.

> **Why this is an invariant and not a new step 2c, nor a two-phase 6d.**
>
> - **A two-phase 6d cannot work.** A reader reaches 6d only *after* step 3, so a "before" phase written inside 6d executes after the change it is meant to precede. **You cannot baseline from a step that runs later than the thing it baselines.**
> - **A new step 2c rots**, in I2's own words: *"an ordering rule silently degrades the next time a step is inserted or renumbered — which is precisely how this bug arose."* 6d is already a victim of exactly that renumbering.
>
> So it is **checked at the point of the first write, like I2**, not asserted as an ordering rule: before the first write of the sync, if `TEMPLATE_DELETED` contains an agent file, refuse until the baseline exists. It is **gated on a non-empty `TEMPLATE_DELETED`**, so it costs an ordinary sync nothing at all.

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

**Smoke test immediately after the `.claude/settings.json` write — probe BOTH WAYS, from a script file.** A harmless `Bash(true)` was the old test here; it proves only that the session is not fail-CLOSED, and a completely inert enforcement layer passes it too. That is the failure mode that actually follows a `settings.json` write, and pre-v2.2.0 on a node-less box this probe would have printed all-zeros and named the silent-gate bug in one line.

**Any hook probe must live in a script file run via `bash <path>`, never inline.** The gates scan the whole command STRING by design, not just what a git subcommand would actually do — an inline compound command that merely *mentions* `git push origin main` (in a comment, an echo, a string literal) trips the gate it is trying to test. The result is then uninterpretable: a block does not tell you whether the gate works or whether your own probe was the violation it caught. Write the probe to a temp file and run `bash <path>` instead.

**A heredoc body is part of the command string too** — `bash <<'EOF' … EOF` is not an escape from the previous paragraph, it is the same string with a different delimiter. Three sessions in two days hit exactly this. Write probe scripts with the **file tool** and run `bash <path>`.

**And check every payload PARSES (`jq .`) before believing a 2.** An unescaped `"` in a JSON payload makes the hook fail closed — at exit 2, which reads as "gated" and is not. A malformed probe and a working gate are indistinguishable by exit code alone.

Write this to `"${TMPDIR:-/tmp}/gate-probe.sh"` (or somewhere under `.claude/`) and run it with `bash "$TMPDIR/gate-probe.sh"`. **Do not** write it to a repo-relative path like `probe.sh` — `enforce-delegation.sh` denies main-thread writes outside the PO write surface, so the probe never gets created.

```sh
H="${CLAUDE_PROJECT_DIR:-.}/hooks"
R="<repo>"   # forward slashes, see the note below

# a. every shipped script must PARSE. One apostrophe inside a `node -e '…'`
#    body ends the shell string early and silently disables that whole hook.
for f in "$H"/*.sh "$H"/lib/*.sh; do
  bash -n "$f" 2>/dev/null || echo "SYNTAX FAIL $f"
done

# b. no-push-main, the one gate that needs no config and touches nothing.
probe() { # <hook> <command>
  printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"cwd":"%s"}' "$2" "$R" \
    | bash "$H/$1.sh" >/dev/null 2>&1
  echo "$1 [$2] exit=$?"
}
for c in "git push origin main" "ls -la" "true"; do probe no-push-main "$c"; done
```

Expect **2**, **0**, **0**. That is the whole routine check: deterministic on every install, no configuration required, and it reads nothing but `PROJECT_CONTEXT.md` and `git branch --show-current`.

**Why only this gate is in the routine probe.** The other two cannot be exercised without doing real work, and their answers are not deterministic:

| gate | its command | returns 2 when |
|---|---|---|
| `no-push-main` | `git push origin main` | always, on a protected branch — needs no config |
| `pre-commit-test` | `git commit -m x` | **only if the suite FAILS.** It *runs* `**Test**`, or `run-gate.sh`, to find out |
| `gate-before-merge` | `git merge feature/x` | only on a protected branch with no fresh artifact |

Measured, and neither case is a corner case: in a `**Test**`-configured repo with a green suite the commit row exits **0**; in a Gate-only repo `pre-commit-test` shells into `run-gate.sh`, which on green **writes `.gate/last-pass.json`** — after which `gate-before-merge` finds a fresh artifact and also exits 0. Feeding all three a shared push-to-main payload is wrong for a different reason again: `pre-commit-test` returns 0 for a push (it gates *commits*) and `no-push-main` returns 0 for a commit or a merge.

> **The two rows below are NOT read-only. They run your full test suite — field-measured at 616 seconds, ~10 minutes, on a real three-project repo — and they can mint a gate artifact.** `pre-commit-test.sh` executes `**Test**`, or `run-gate.sh` when there is no `**Test**` field, and a green `run-gate.sh` writes `.gate/last-pass.json` keyed to the current HEAD/tree. That artifact is exactly what `gate-before-merge.sh` looks for, so a probe run can leave a *real* merge un-gated until it expires (60 minutes). Run these deliberately, on a repo you are already building in, and `rm -f .gate/last-pass.json` afterwards. Never as part of a routine sync.
>
> ```sh
> probe pre-commit-test   "git commit -m x"      # 2 only if the suite FAILS
> probe gate-before-merge "git merge feature/x"  # 2 only on a protected branch,
> ```                                            #   with no fresh artifact
>
> A 0 from either proves nothing on its own — check its condition in the table above before drawing a conclusion. If `pre-commit-test` returns in about a second, it did **not** run your suite; the hook prints `passed. (<n>s)` precisely so the two are distinguishable, since a green run deletes its captured output.

**Both halves are the test, and `2 0 0` is the only healthy answer.** `2 2 2` means the session is fail-CLOSED — every Bash call is about to be blocked; take the recovery note below. **`0 0 0` means enforcement is GONE** — the scripts are missing, empty, unparseable, or not wired — and the sync is running unprotected: apply `hooks/lib/git-cmd.sh` and the three gate scripts via `template_apply_file`, then re-run the probe before continuing. The old `Bash(true)` test could not tell that second failure from success at all, which is why it is gone.

**Say precisely what `2 0 0` proves, because we said it wrong for two releases.** This probe feeds payloads to the scripts directly, so the harness is never in the loop: `2 0 0` proves **the scripts parse a payload and behave correctly on it**. It does **not** prove the hook FIRES. Whether the harness invokes them is a separate question needing a separate instrument, and **timing a `git commit` from inside the command is not that instrument**: a PreToolUse hook completes *before* the Bash tool runs the command, so a timer started inside it can never observe the hook, and a fast command is not evidence the hook did not fire. What does answer it is a side effect that outlives the interval — assert a marker file as the **FIRST** statement of your own command; PRESENT proves the hook ran and completed ahead of it — or a clock read from outside, across two consecutive tool calls.

One thing this probe deliberately does not tell you: whether the branch you are on is the one you meant to protect. It fires on `main` because `main` is in the default set. If your trunk is `develop`, `2 0 0` here says the hook works — not that `develop` is covered. Check `**Protected branches**:` for that; the block message names the set it resolved.

> `enforce-delegation.sh` is deliberately NOT in that loop. It signals a deny by printing a `permissionDecision` on **stdout** and always exits 0, so an exit-code probe reads every case as PASS and proves nothing about it. Probe it by grepping its stdout for `"permissionDecision":"deny"` instead.

Use **forward slashes** in the JSON `cwd` (`C:/git/foo`, not `C:\git\foo`): a Windows backslash is a JSON escape and the payload will not parse. Since v2.2.1 the gates BLOCK an unparseable payload rather than passing it, so this now shows up as a spurious all-2 rather than a false green — still a wrong answer, just a louder one.

> **Recovery — if every Bash call is blocked mid-sync:** apply `hooks/lib/git-cmd.sh` and then the three gate scripts (`pre-commit-test.sh`, `no-push-main.sh`, `gate-before-merge.sh`) via `template_apply_file`, which needs no shell. Do **not** restart the session first — the half-applied state persists on disk, and a restart only re-reads the same broken combination. Once Bash works again, finish the sync in the order above and restart per the final report.

Collect all results. Report the list of auto-updated files.

### 4. Resolve Conflicts

For each file with status `CONFLICT`:

1. Call `template_get_diff(project_path=".", file_path=F, diff_type="three_way")`
2. **Disqualify the unsafe options BEFORE offering anything.** Both of these are checks on the diff you just fetched:
   - *Accept merged* is off the table unless `auto_merged` survives inspection: diff it against BOTH `template_content` and `project_content` for lines present in base AND project; if any are missing, do not offer it — a clean merge is not a correct merge. For `hooks/*.sh`, also `bash -n` the merged body (and `node --check` any embedded `node -e` block); a syntax error is a conflict, not a clean merge.
     > **Run `bash -n` through a `which`-RESOLVED absolute path, never a bare name and never a hardcoded one (v2.2.5).** Driven from a scripting language on Windows, the bare name `bash` does not resolve to the shell you meant: `shutil.which('bash')` reports `C:\Program Files\Git\usr\bin\bash.EXE`, while `subprocess.run(['bash', …])` executes **WSL** bash, which cannot see a Windows path. Python's own two mechanisms disagree about the same **NAME** — and that is the entire root cause. They cannot disagree about an absolute path. So the fix is one host-agnostic line with no platform knowledge in it:
     >
     > ```python
     > exe = shutil.which("bash")     # resolve ONCE, by name, here
     > if exe is None:
     >     ...                        # could not check — name the interpreter and stop
     > subprocess.run([exe, "-n", script], ...)   # then only ever exec the absolute path
     > ```
     >
     > Measured on the reporting Windows host (Git for Windows + WSL both installed), all four verdict columns, every candidate interpreter:
     >
     > ```
     > interpreter                             valid  broken  missing  directory
     > bare name 'bash'                          127     127      127        127   <- indistinguishable
     > shutil.which('bash')  (Git\usr\bin)         0       2      127        126
     > C:\Program Files\Git\bin\bash.exe           0       2      127        126
     > C:\Program Files\Git\usr\bin\bash.exe       0       2      127        126   <- IDENTICAL to bin
     > ```
     >
     > **An earlier revision of this step told you to hardcode `C:\Program Files\Git\bin\bash.exe` and warned against the `usr\bin` path `shutil.which` reports. Both halves are withdrawn.** The last two rows are the comparison that warning was written without: `bash -n` parses without executing, needs no path translation, and the two binaries behave identically. And the hardcoded path **does not exist on Linux, WSL or macOS**, so shipping it makes the check unrunnable everywhere else — while any fallback to the bare name restores the Windows bug it was meant to fix. An unmeasured warning is worse than no warning: it makes the next reader distrust the correct binary.
     >
     > **Then read the result by this table. `rc=127` is a HARD ERROR, not "the check did not run":**
     >
     > ```
     > FileNotFoundError  -> could not check; name the interpreter. THIS is "the check
     >                       did not run" — it is an EXCEPTION, raised before any exit
     >                       code exists, not a return code. Verified: an interpreter
     >                       that is absent raises; it never yields an rc.
     > rc 0               -> pass
     > rc 2               -> syntax error — the ONLY fail verdict
     > rc 126             -> could not READ it: permissions, or a DIRECTORY passed where
     >                       a script was expected. ERROR; print the path
     > rc 127             -> bash could not find THE FILE. ERROR; print the path
     > anything else      -> unknown. ERROR
     > ```
     >
     > **Why 127 is an error rather than a shrug, and why the previous wording was a fail-open.** `rc=127` is bash's own verdict about the file it was handed — *"No such file or directory"*. It is not "the interpreter failed to launch". Treating it as did-not-run waves through `bash -n hooks/deleted-thing.sh` on a manifest that still references a script no longer on disk — and **a missing hook script is exactly the condition this toolkit's 127-wrapper exists to catch** (a hook whose script is gone exits 127 and the tool call proceeds). Recording it as "unknown, carry on" would reinstall that fail-open one layer up, inside the checker. The all-127 row above was bash correctly reporting that none of the three paths was visible to the bash that actually ran — a fact about the *invocation*, which the `shutil.which` line is what fixes. The same table applies to `node --check` and to any other checker invoked by name. (This is the `command -v python3` App-Installer stub class again: the name resolves, the program is not the one you meant.)

   - *Accept template* is off the table when it would silently drop project content: an EMPTY `PROJECT-CUSTOM` region while headings the template does not carry sit outside it (list those headings), or — for `.claude/settings.json` — a `matcher` string naming agents the template version no longer mentions, e.g. a project-added `cpp-coder` (list those agent names; accept-template reverts their hook wiring). In either case route to the splice path (`source="provided"`) instead.
3. Present what is left:
   - If `has_conflicts` is **false** and `auto_merged` passed step 2: show it and offer to apply.
   - Otherwise show the conflict markers and the `unified_diff`, and ask the user how to resolve, offering only the options step 2 did not disqualify:
     - **Accept merged** (if they edit the merged content)
     - **Accept template** (discard local changes)
     - **Keep mine** (acknowledge template change but keep project version)
     - **Splice** (`source="provided"` with hand-merged content)

     > **⚠ A `hooks/*.sh` SPLICE MUST NOT BE APPLIED WITH THE `Edit` TOOL.** `enforce-delegation.sh` denies main-thread `Edit`/`Write`/`NotebookEdit` outside the PO write surface, and `hooks/` is not on that surface — a hook script is enforcement code, and the PO hand-editing it is exactly what the rule exists to prevent. **That deny is correct and long-standing; do not work around it and do not reach for `.claude/delegation-off`.** The sanctioned route is `template_apply_file(source="provided", content=...)`, composing the merged content in a script rather than by hand, followed by `template_apply_file(source="skip")` to register the result. This is the modal conflict for any consumer carrying a gate deviation, so the route has to be named here rather than discovered: a consumer who got through did so by using `template_apply_file` plus a script for unrelated reasons — luck, not design.

4. Apply the user's choice:
   - Accept merged/template: `template_apply_file(source="provided", content=...)` or `template_apply_file(source="template")`
   - Keep mine: `template_apply_file(source="skip")`

> **PROJECT-CUSTOM region:** the server preserves content between `<!-- PROJECT-CUSTOM:BEGIN -->` and `<!-- PROJECT-CUSTOM:END -->` mechanically (when both template and project carry the markers). If the consumer's `template-sync-tools` server predates region support, preserve the project's region verbatim in any manual `CLAUDE.md` merge — never let accept-template clobber it.
>
> Since v2.1.2 the markers also ship at the end of every `.claude/agents/*.md` and of `AGENT_TEAM.md` — the region split is file-agnostic, so those files now merge exactly like `CLAUDE.md`. On the first sync that brings the markers in, **move the project's existing custom agent lines into the region once**; anything left above the BEGIN marker is template territory and the next accept-template will overwrite it.
>
> "EMPTY region" in the accept-template disqualifier above means *no content other than the shipped `<!-- Project-specific rules, routing blocks, and extensions go here. -->` placeholder* — the placeholder alone does not make a region non-empty.
>
> ### ⚠ DO NOT IMPLEMENT THAT CHECK. RUN THE SHIPPED ONE (v2.4.0).
>
> ```
> bash "$(dirname "$0")/region.sh" --scan .        # classify every region-bearing file
> bash "$(dirname "$0")/region.sh" --body <path>   # the region body, verbatim
> ```
>
> `region.sh` ships next to this file. **Two independent consumers implemented "is the region empty?" from the paragraph above and both got the REASSURING answer wrongly**, which is why it is now code:
>
> - `PROJECT-CUSTOM:BEGIN\s*-->` matches **nothing** — the shipped marker carries trailing prose: `<!-- PROJECT-CUSTOM:BEGIN — sync-template preserves everything between these markers -->`
> - `glob('**/*.md', recursive=True)` does **not** descend into dot-directories, so it skips all of `.claude/` — every agent file.
>
> One consumer measured **"zero regions" across a repo with eleven.** A consumer who implements this by hand concludes *"empty"*, clears the disqualifier, and accept-template destroys the region. The specification `region.sh` implements, so you can read it without reading the script:
>
> ```
> regex : PROJECT-CUSTOM:BEGIN.*?-->(.*?)<!--\s*PROJECT-CUSTOM:END      (DOTALL)
> scope : enumeration MUST include dot-directories (.claude/ especially)
> empty : body is whitespace or the shipped placeholder comment only
> ```
>
> **`--scan` is the ONLY enumeration this skill documents.** Two documented ways to enumerate is how the naive glob came back; take the file list from `--scan`'s output rather than writing a second walker.
>
> **AND THE COROLLARY REACHES BACKWARDS: every consumer who has ever reported *"no PROJECT-CUSTOM content here"* may have been reporting their EXTRACTOR, not their repo.** Re-check with the shipped one before trusting any earlier all-clear — including your own from a previous sync.
>
> The defect lives in the unspecified implementation, the same class as `--include` after paths, the `which`-resolved `bash -n`, and the `command:`-anchored collector. **The population bitten is the consumers who follow us most literally.**

> **`PROJECT_CONTEXT.md`: SPLICE, never accept-template.** It conflicts for every consumer who has filled in real values, and accept-template replaces a working `- **Gate**: npm run gate` with `{{GATE_COMMAND}}` — which silently disables `pre-commit-test.sh` and `run-gate.sh` on the next commit, worst on a Gate-only repo where nothing else notices. Your `**Gate**:` / `**Test**:` / `**Build**:` values live in this file; they are a legitimate, permanent deviation, not drift to clean up. Take the template's *new lines* by hand and keep your own values.
>
> **TWO FIELD-NAME STYLES SHIP, and until v2.2.6 this skill named only the short one (consumer report).** Grepping your own `PROJECT_CONTEXT.md` for `**Test**:` returns nothing on a python or java project and reads as *"the gate is unconfigured"* — a false clean one layer up, in prose rather than in a regex. Measured across all six variants:
>
> ```
> general / dotnet / dotnet-maui    **Build**          **Gate**          **Test**
> python / java                     **Build Command**  **Gate Command**  **Test Command**
> rust-tauri                        **Build**          **Gate**          (no Test — deliberate)
> ```
>
> **The HOOKS are fine** — `pre-commit-test.sh` greps `\*\*Test( Command)?\*\*:` explicitly, and the other field greps tolerate the long form the same way. Only the documentation was narrow. So whenever you grep for one of these fields, match both: `grep -E '^[-*[:space:]]*\*\*Test( Command)?\*\*:'`.
>
> **rust-tauri's absent `**Test**` is NOT a defect.** No Test ⇒ `pre-commit-test.sh` falls back to Gate ⇒ it runs `run-gate.sh`, which also mints the artifact. That is the deliberate v2.1.1/v2.1.3 Gate-only shape. The consequence worth knowing: a rust-tauri consumer runs the **full Gate on every commit** and never gets v2.2.5's Test/Gate split. Adding a fast `**Test**` line is a local choice, not a sync fix.
>
> **`**Protected branches**:` is the one line the git gates read** — the `- **Branch strategy**:` prose above it is for humans and is parsed by nothing. Cheapest proof the config path works: attempt a push to trunk and read the block message, which names the set it actually resolved — `BLOCKED: pushing to a protected branch (main master)` vs `(develop release)`. Absent, empty, or still a `{{...}}` all resolve to `main master`; `none` is the one deliberate way to protect nothing (branch rules only — a PR merge stays gated whatever the branch).

### 5. Handle New Files

`new_template_files` means **absent from the manifest**, NOT absent from the project (invariant I1 above). So for each file in `new_template_files`, **check the disk BEFORE asking anything**:

1. **The path already exists in the project → this is a CONFLICT, not a new file, and not a silent skip.** Both sides have content, which is the definition of a conflict. Fetch `template_get_diff(project_path=".", file_path=F, diff_type="three_way")`, **show the diff**, and offer the normal step-4 options — **with keep-mine as the default**:
   - **Keep mine** (DEFAULT) → `template_apply_file(project_path=".", file_path=F, source="skip")`, which registers a manifest entry from the project's existing content and writes nothing, exactly as step 6b rule 4 prescribes for a present-but-untracked hook.
   - **Accept template** → only on an explicit choice made against the diff; this overwrites their file.
   - **Splice** (`source="provided"`) → hand-merged content.

   Do not reduce this to a silent skip. Skipping is safe but it *hides* that the template ships a different version of a file the project already has — the consumer who lost a file this way would have been told nothing, and would never have learned the template's `run-gate.sh` existed and differed. That comparison is what produced the whole of item K.
2. **The path does not exist** → ask the user whether to add it. If yes: `template_apply_file(project_path=".", file_path=F, source="template")`.

**`source="template"` appears in this step ONLY inside case 2, and that is deliberate.** An earlier revision presented it as the default with a condition that might override it; a reader executing literally reached the destructive call and the condition lost, even though a rule of exactly the same shape (6b rule 4) was already written down and had been read. **The imperative at the point of action beats the rule stated elsewhere**, so the branch — not the invariant — is what has to make the wrong call unreachable. Invariant I1 above is the backstop, not the fix.

**List every path you took through case 1, individually.** Report them under `Skipped:` (or `Conflicts:` where the user chose otherwise) as *present on disk — resolved `<resolution>`*, one line per path, never as a count. A count is how a consumer fails to notice that the one file they cared about was in the set.

**Post-apply guard — verify the keep-mine files were not written, and make the guard's own failure visible (v2.2.5).** After the last write in this step:

- **Check set: every keep-mine path that step 2b's SPECIFICATION covers** — `keep-mine ∩ (set a ∪ set b)`, where 2b's two backup sets are **(a)** gitignored ∩ manifest-tracked and **(b)** `new_template_files` ∩ exists-on-disk. Byte-compare each against its backup copy; any difference is a data-loss event, and at that moment it is still recoverable *from the backup*.
- **DERIVE THE SET FROM 2b's RULES, NEVER FROM THE BACKUP DIRECTORY'S CONTENTS (v2.2.5 round 4).** "Keep-mine paths present in the backup" makes the coverage assertion below **vacuous by construction**: a 2b derivation failure then silently shrinks the check set until the guard passes — a guard failing by reporting success, guarding a bug whose entire signature is failing by reporting success. Derive from the rules, assert each member has a backup entry, then compare.
- **Scope it by the RESOLUTION, never by the path list.** A file the user explicitly resolved **accept-template** is *supposed* to differ and is exempt; keying the guard on `new_template_files` instead would fire on a correct, user-approved outcome, and the fix for that false positive is to weaken the guard, which reopens the hole. This is the same shape as the bug the step itself fixes: **a guard must be keyed on the decision that was made, not on the list the file arrived in.** The discriminator already exists and is populated — `source="skip"` records `"resolution": "keep-mine"` on the manifest entry; template and provided applies omit the key.
- **NO STEP ATTRIBUTION ANYWHERE (v2.2.5 round 4, and this replaces the blanket step-4 exclusion).** The earlier wording excluded *step-4 keep-mine files as a category* — keyed on **which step produced the resolution**, when the property that matters is **whether 2b's specification covers the path**. Those diverge, and in the direction that loses coverage: **a step-4 keep-mine file that is gitignored is in set (a)**, so it *is* backed up, the comparison *would* work, and the blanket exclusion drops it anyway — manifest-tracked, gitignored, resolved keep-mine: no history, no diff, no undo, exactly the class 2b exists for. **`CLAUDE.local.md` resolved keep-mine in step 4 is the routine instance, not a corner case.** With the set defined by 2b's rules, step-4 non-gitignored files fall out on their own (2b does not cover them) and the special case disappears. This is the provenance error one layer down from the one the release keeps closing: *keyed on who decided, when what matters is what the spec covers.*
- **Assert the backup COVERS each path before comparing it — a missing backup entry is a HARD ERROR, never a clean pass.** Say why, or the next reader deletes it as a redundant existence check in front of a comparison: a byte-comparison against a backup that does not contain the path finds nothing to compare and **reports success**. That is a guard failing by reporting success, guarding a bug whose entire signature is failing by reporting success. `no backup entry for <path>` stops the sync.
- **Control, both arms.** Deliberately drop one check-set path from the backup and confirm you get the hard error, not a clean run; then restore it and confirm the run is clean. A coverage assertion is the easiest thing in this file to write in a way that passes whether or not it exists — verify it by removing it and watching the first arm go green, which is the only test that tells you the truth.

Apply new libs and hooks BEFORE `.claude/settings.json` is written, even though this step is numbered after step 3 (invariant I2).

> **Upstream:** `template_compute_status` should carry `present_on_disk: true` on `new_template_files` entries so a client cannot get this wrong — filed on `mcp-dev-servers`. Until it lands, the disk check above is the only thing between a consumer and a silent overwrite, and it depends on the agent remembering to make it.

**Duplicate-load warning:** for a new `.claude/rules/*.md`, grep `CLAUDE.md` for each of its headings. A heading present in both means the project pasted that section into `CLAUDE.md` before the template extracted it into a path-scoped rule — it would now load twice. List the duplicated headings and offer to delete the `CLAUDE.md` copy.

### 6. Handle Template-Deleted Files

### ⚠ 6a. A FILE WHOSE PROJECT-CUSTOM REGION IS NON-EMPTY CANNOT BE DELETED (v2.4.0, item A2)

**Run this BEFORE anything else in this step, on every `TEMPLATE_DELETED` path:**

```
bash "$(dirname "$0")/region.sh" <every TEMPLATE_DELETED path>
```

`CONTENT` (or `UNCLOSED`) on any path ⇒ **deletion is NOT OFFERED for that path.** Not defaulted away from, not behind a second confirmation — **absent from the option list.** The only available actions are **relocate the region** to a named survivor, and **defer**. Once the region is empty, the ordinary flow below applies.

**Why a precondition and not an acknowledgement.** Step 6 has until now asked exactly one question — *is it still referenced* — and **never inspected the region**. A consumer with custom routing in `coder.md` is told *"preserved and unreferenced — safe to delete"*, accepts, and `git rm` takes it. **The prompt that asked for consent never showed the thing being destroyed.** A second acknowledgement does not fix that: a prompt loses to fatigue, and someone who has cleared four prompts clears the fifth. Step 5 was not fixed by making `source="template"` the non-default; it was fixed by making it **unreachable** outside the not-present arm. This is the same shape.

So the user cannot choose *"delete with content"*; they can only *"empty, then delete"* — and emptying is the act that moves the content somewhere it survives. **The irreversible step becomes reachable only once the content is provably elsewhere.**

**This is the MODAL case in a consolidation release, not an edge case.** All nine shipped agent files carry PROJECT-CUSTOM regions and are manifest-tracked, so `TEMPLATE_DELETED × region-bearing` can fire **up to nine times in one sync**.

Required, in order:

1. **Extract with `region.sh`** — the shipped extractor, never a hand-written check. A2 is unsound without it: the hand-written version returns the *reassuring* answer (see step 4's note), a region with content reads as empty, deletion is offered, and the content is gone.
2. **`CONTENT` ⇒ print the region VERBATIM** (`region.sh --body <path>`) and **withhold the delete option entirely**. Show the user what is at stake in the same breath as the question.
3. **Offer relocate (to a named survivor) or defer.** After a relocate, **BYTE-COMPARE the moved region against the original before deletion becomes reachable**:

   ```
   bash region.sh --body <original>  > "$TMPDIR/region-orig"
   bash region.sh --body <survivor>  > "$TMPDIR/region-moved"

   # NON-EMPTY *AND* EQUAL. Both conditions, in this order.
   [ -s "$TMPDIR/region-moved" ] || FAIL "the survivor's region is EMPTY — the relocate did not happen"
   cmp "$TMPDIR/region-orig" "$TMPDIR/region-moved" || FAIL "the moved region differs from the original"
   ```

   **⚠ EQUALITY ALONE IS SATISFIED BY TWO NOTHINGS, and that was measured on real fixtures, not imagined (v3.0.0):**

   ```
   two files whose regions are both empty (the relocation never happened)
     --body rc: orig=0  moved=0        bytes: orig=0  moved=0
     cmp: IDENTICAL  ->  the relocation gate PASSES
   ```

   `cmp` on two zero-byte bodies succeeds, so a `cmp`-only check **certifies a relocation that never occurred** and then unlocks the irreversible step. The non-empty test is what makes the proof carry content. This is the same shape as a control that cannot fail in the environment it runs in — a check whose success state is indistinguishable from its no-op state.

   **Make "provably" MECHANICAL, not asserted** — a positive check carrying content, the same discipline as a planted-marker control, rather than the user's word that they handled it.

> **Step 2b's backup is a good floor, but recoverable is not the same as noticed.** A consumer who does not realise they lost something never goes looking in the backup. That is why this is a precondition and not merely a backup.

### ⚠ A2 AND SET (c) COVER **DISJOINT** POPULATIONS — do not read A2 as "my customisations are protected"

Measured on a consumer's live synthetic `TEMPLATE_DELETED` run, and it is the single most likely misreading of this section:

```
set (c), disk-scoped   : 11 files
manifest-scoped        : 10 files
delta                  : .claude/agents/game-tester.md   <- exactly the irreplaceable file
                         verdict: NOMARKERS
```

**A2 protects REGION-BEARING files. The irreplaceable file is not one.** A hand-authored, project-owned agent has no PROJECT-CUSTOM region at all, so it classifies `NOMARKERS`, and `NOMARKERS` is reached by the **ordinary** flow — 6a offers it for deletion and withholds nothing. That behaviour is *correct*: there genuinely is no region to protect. But it means the natural reading — *"A2 protects my customisations"* — **is false for precisely the file nobody can regenerate.**

The orphan's only defences are elsewhere, and both must hold:

1. **Step 2b's set (c)**, scoped to what the destructive operation TOUCHES rather than what the manifest KNOWS — which is the whole reason A3 was rescoped;
2. **Step 6's rule that a project-owned file the template never shipped is never deleted.**

Two guards, two disjoint populations, and **a reader will assume they overlap.** That assumption is what gets the file deleted, so it is written down here rather than left to be inferred.

**Also confirmed by the same run, so it is not in doubt:** 6a discriminates correctly in a single pass — a planted `CONTENT` region withheld deletion while an untouched placeholder-only file classified `EMPTY` and was offered. The discrimination works. It was the *inputs* that were unsound before v3.0.0's marker-shape fix.

> ***"Unreferenced" answers whether enforcement breaks; it says nothing about whether the user loses work.***

### 6 (continued). The ordinary TEMPLATE_DELETED flow

Reached only for paths 6a classified `EMPTY` or `NOMARKERS`. For each such file:

1. Determine whether anything still references it: run the same reference grep as step 6b (`.claude/settings.json` plus the `hooks:` frontmatter of every `.claude/agents/*.md`), **and the agent-NAME sweep in 6d below**.
2. Report the state precisely:
   - "preserved **and unreferenced — safe to delete**" — the new `settings.json` and agents no longer mention it;
   - "preserved **and still referenced by `<file>`**" — deleting it would take enforcement offline.
3. ASK the user. Recommend accepting the deletion in the unreferenced case; delete with `git rm <file>` so the removal is in the diff. Never delete on your own initiative, and never delete a project-owned file the template never shipped. (`git rm` here, and `git add`/`git commit` in step 9, are the PO's documented git-I/O role for this skill per `AGENT_TEAM.md` — not hands-on coding.)

   > **UNATTENDED (no user in the loop) — the default, stated so it is not improvised.** Delete ONLY a path that is all three of: classified `EMPTY`, shipped by the template, and unreferenced by the step-6b grep and the 6d name sweep. **DEFER everything else** — `CONTENT` and **`NOMARKERS` included**: keep the file on disk, keep its manifest entry, and report it. `NOMARKERS` is exactly what a hand-authored, project-owned agent classifies as (set (c), the game-tester case), so an autonomous branch that treated NOMARKERS as deletable would delete the one file nobody can regenerate. **The rule "never delete a project-owned file the template never shipped" applies in the autonomous branch explicitly** — an unattended run is where an implied rule dies.

   > **Acknowledging a kept file so it stops re-reporting: the MANIFEST, beside `files`.** A `TEMPLATE_DELETED` path the project decided to KEEP re-reports on every future sync. The acknowledgement is a `"deletedAcknowledged": ["<path>", ...]` list in `.claude/template-manifest.json`; `compute_status` then reports those paths as `ACKNOWLEDGED_KEPT` instead of `TEMPLATE_DELETED`. This is **distinct from `deleted_files`**, which drops the entry entirely. The intended surface is `template_finalize_sync(acknowledged_deleted=[...])` — **a server change in `mcp-dev-servers`, landing on that repo's next release, not in this one.** Until it ships, add the key by hand: LF endings, existing key order preserved, the same relative paths `files` uses. It is the manifest and not `PROJECT_CONTEXT.md` deliberately: that file is keep-mine project content, and a sync-owned key there would be a key the tool writes into a file it otherwise never touches.
   - **Ordering:** delete a template-removed hook only AFTER the new `.claude/settings.json` has been applied (step 3's order) AND the step-6b reference grep — re-run against that new `settings.json` — shows it unreferenced. Deleting it while the in-memory settings still wire it makes every matching tool call exit 127 and fail closed for the rest of the session.
4. **For ANY deleted file, cross-reference its user-level twin — this is not a hooks-only rule.** The dangerous twin lives under `~/.claude/` (`hooks/<name>.sh`, `agents/<name>.md`, `skills/<name>/SKILL.md`), which **no project sync touches**. Tell the user to remove it there too (see the CHANGELOG's downstream-migration notes).

   > **Why it was written hooks-only, and why that was wrong.** The original wording said *"for a deleted **hook**"*, on the reasoning that a stale hook fails closed. **v3.0.0 deleted AGENTS**, and the reasoning transfers exactly: a retired agent surviving at `~/.claude/agents/<name>.md` stays **spawnable** after the project file is gone — the retirement is undone at user level, silently, for every repo on the machine. A consumer checked `~/.claude/agents/` anyway, because they generalised it themselves. Do not make the next one do that. **The scope is the DELETION, not the artefact type.**

### 6b. Verify Hook Scripts (MANDATORY)

Hooks fail OPEN when their script is missing (exit 127 → the tool call proceeds with only a non-blocking error). A synced project with a populated `.claude/settings.json` but an empty `hooks/` directory runs with its entire enforcement layer silently absent — this happened in production.

> Read the toolkit working tree with Read/Grep, never through the context-mode sandbox: `git -C` fails silently on its `/tmp` paths and `grep -c` comes back 0, so every verification below would report a false clean.

1. Collect every `hooks/<name>.sh` reference in `.claude/settings.json` AND in the `hooks:` frontmatter of every file in `.claude/agents/`. **Collect the PATH; do NOT anchor on the `command:` value:**

```
grep -o 'hooks/[A-Za-z0-9_.-]*\.sh' .claude/settings.json .claude/agents/*.md | sed 's/^.*://' | sort -u
```

> **Anchoring on `command:` is the v2.2.5 defect, and it recovered ZERO (v2.2.6, consumer measurement).** Until v2.2.6 this step said "on a `command:` line", justified as keeping the `Bash(bash hooks/run-gate.sh*)` PERMISSIONS pattern out of the set. But the hook path sits **after an escaped quote** inside the command value, so the obvious implementation truncates at the escape:
>
> ```
> grep -o '"command": "[^"]*'            ->  "command": "bash \        <- truncates AT the escape
> grep -o 'hooks/[A-Za-z0-9_.-]*\.sh'    ->  12
> ```
>
> A consumer collected **5 of 12** and printed `Hooks verified: 5 referenced, 5 present` — a clean-looking verify with **seven hooks unchecked**, in the one step that exists because a populated `settings.json` over an empty `hooks/` runs with enforcement silently absent. All five came from this step's two *unanchored* collectors (3 from agent frontmatter, 2 from the lib grep in 1b); the single anchored collector contributed nothing. **The step already succeeded everywhere it did not anchor.**
>
> **Why it survived a release is the durable half:** a **zero** would have looked broken; a **partial** read as plausible. The anchor bought protection against a harmless false positive at the cost of a silent false clean.
>
> Over-collection is the correct trade here, exactly as rule 1b already blesses it for libs. The one false positive (`hooks/run-gate.sh`, from the permissions pattern) is a real, tracked file: it costs one existence check and nothing else. And matching the PATH matches every invocation form at once — the legacy cwd-relative `bash hooks/<name>.sh`, the v2.1.2 `bash "$CLAUDE_PROJECT_DIR/hooks/<name>.sh"`, and whatever form is invented next.
1b. Collect the **libs** too — a hook that cannot reach its lib defines no helpers, reads an empty command, and exits 0 on everything. In every hook script present at the project root, grep for **any** `lib/<file>.sh` mention, in any form:

```
grep -oE 'lib/[A-Za-z0-9_.-]+\.sh' hooks/*.sh | sort -u
```

Add each hit as `hooks/lib/<file>`. They are checked and restored exactly like the scripts in steps 2–4 (`source="template"` when missing — the server resolves the `hooks/lib/` subdirectory against the toolkit root).

> **Match the FORM, not one form.** Until v2.2.1 this step named a single pattern — the `. "$(dirname "$0")/lib/…"` **source** form, plus a literal `lib/git-cmd.sh`. Every node-program hook references its lib as an **assignment** instead (`jlib="$(dirname "$0")/lib/json.sh"` in `bash-output-guard`, `enforce-agent-contract`, `enforce-delegation`, `read-size-gate`, `require-skills-block`, `retro-brief`, `retro-ledger`), so an agent following this step *literally* never collected `hooks/lib/json.sh`, never noticed it missing, and those seven hooks disabled themselves while the sync report said clean. The three git gates were unaffected — they source `lib/git-cmd.sh` behind a hard `[ -f … ] || exit 2` and fail CLOSED. Over-collecting is harmless: a lib already present is a no-op, and a lib named only in a comment still resolves to a real file.
1c. **Cross-check the collected count against an INDEPENDENT source before trusting it (v2.2.6).** The defect above did not announce itself: it produced a number, and every file behind that number really was present, so `5 referenced, 5 present` read as a clean verify. **A collector returning a partial result reads as success** — the fixture-that-passes-vacuously class, one layer out. The counts alone cannot tell you the collector worked; a second, differently-sourced count can.

```
referenced=$(grep -o 'hooks/[A-Za-z0-9_.-]*\.sh' .claude/settings.json .claude/agents/*.md | sed 's/^.*://' | sort -u | wc -l)
on_disk=$(ls hooks/*.sh 2>/dev/null | wc -l)     # the FILESYSTEM, not the config text
```

**Assert `referenced >= on_disk`, and LIST every on-disk hook that appears in neither file.** The two numbers come from different places — one from configuration text, one from the directory — so a truncating regex moves only the first. The observed failure prints `5 referenced, 12 on disk, 7 unreferenced: [...]`, which cannot be read as clean.

`referenced < on_disk` is not automatically a defect: a project may legitimately carry a hook nothing registers. It is a **stop-and-name-them** condition, not a stop-the-sync condition — every unreferenced hook is listed in the report with the reason it is unreferenced. What is NOT acceptable is a bare count that nobody compared to anything.

> **Verify this cross-check by DELETING the guard it protects.** Re-anchor the step-1 grep on `"command": "[^"]*` and re-run: `referenced` must collapse and the unreferenced list must fill up. A cross-check that stays green with the anchor restored is testing the surrounding machinery, not the collector.

2. For each referenced script: verify `hooks/<name>.sh` exists at the project repo root and is non-empty.
3. For any MISSING script: call `template_apply_file(project_path=".", file_path="hooks/<name>.sh", source="template")` — the server resolves root-tracked `hooks/` paths against the toolkit ROOT (variants do NOT ship `hooks/` — never look in `templates/<variant>/hooks/`, it does not exist) and both materializes the file AND returns its manifest entry in one call. Never hand-copy. Add each result to the collected `applied_files`.
4. For every referenced hook script PRESENT at the project root, NOT tracked in the manifest, AND NOT already applied by step 3 (the two sets are disjoint): call `template_apply_file(project_path=".", file_path="hooks/<name>.sh", source="skip")` and add the result to `applied_files`. `source="skip"` registers a manifest entry from the project's existing file content WITHOUT writing — NEVER use `source="template"` here, it would silently overwrite locally-edited hook scripts. Once registered, future `template_compute_status` runs track hook drift like any other file.
5. Report the verified list, **including the independent count from 1c** — the cross-check is worth nothing if its second number never reaches the report:

```
Hooks verified: N referenced, N present (M restored, K registered in manifest); D on disk, U unreferenced: [list]
```

### 6d. Sweep for agent NAMES, not just `hooks/` paths (MANDATORY when an agent file is TEMPLATE_DELETED — v2.4.0, item A4)

**A consolidation deletes agent FILES. It does not touch REFERENCES TO THEIR NAMES**, and step 6's reference grep looks for `hooks/` paths only. Measured on a live consumer: a **keep-mine `CLAUDE.md`** carries an agent-selection table naming `python-coder` and `coder` as `subagent_type` values, with an explicit instruction not to substitute one for the other. `AGENT_TEAM.md` and `settings.json` are template-owned, so the template updates them — **`CLAUDE.md` is keep-mine and is therefore NEVER updated.** The sync completes clean, step 6 reports the deleted agents unreferenced (*truthfully, for `hooks/` paths*), and the next spawn of a consolidated-away agent fails at runtime against instructions the project still carries.

> This is *removals fail closed* **one layer out**: the removal does not break the hook layer, it breaks **a project-authored instruction that no longer resolves.**

#### ⚠ KEY ON THE REFERENCE FORM, NOT THE NAME — a bare name grep is 28:1 noise and dies on first use

Measured on a live consumer, `.claude/agents/` excluded:

```
name hits in project prose:  coder 74 | tester 32 | architect 27 | code-reviewer 16
                             Explore 13 | ops 12 | doc-generator 10 | req-eng 7 | test-writer 4
                             ------------------------------------------------- total 195
lines actually referencing subagent_type:                                             7
```

`coder` alone is **74 hits**, essentially all of it prose discussing the role. **A consumer runs that once, sees 195 hits, and never runs it again** — the exact *noisy enough to be ignored* failure, and the same one already rejected for the placeholder sweep. **Match the reference SHAPE**, exactly as the sweep's markdown arm requires a `- **Key**: value` line rather than any occurrence of the key. **195 → 7 on that repo.** *Scope is the right axis; the name set is not.*

#### The five binding forms — ONE PASS PER PATTERN LANGUAGE, NOT ONE PASS PER NAME

A consumer enumerated every place an agent name is bound. **Only one of the five is a spawn call, and two of them fail OPEN and SILENT.**

| # | Form | Failure mode when the name retires |
|---|---|---|
| 1 | Hook `case` arms — `coder\|*-coder)`, `tester)`, `architect)` | **FAIL OPEN, SILENT** — falls to the default arm; the spawn proceeds with **no skills requirement**, no error, no log line |
| 2 | `settings.json` matcher regexes — `^([a-z0-9]+-)?coder$\|^tester$` | **FAIL OPEN, SILENT** — the hook is **never invoked at all**. Not a block, not a warning |
| 3 | `CLAUDE.md` routing prose — *Rust/Tauri → rust-coder, do not substitute* | dangling mandate, permanent in a keep-mine file |
| 4 | Agent frontmatter cross-refs — every agent file names others | dangling reference |
| 5 | **Hook user-facing output strings** — `enforce-delegation.sh`'s DENY text names `coder`, `ops`, `tester` | not enforcement, but a live instruction telling a blocked user to spawn something that no longer exists |

> **This inverts the comfort premise that a retired name "fails loudly at spawn".** It fails **loudly when spawned** and **silently in every hook that keyed on it** — opposite polarities in the same release, and the loud one is the one that got measured. Loudness protects the *caller*; it does not protect the *enforcement layer*.

**Forms 1 and 2 are the same intent in two different pattern languages** — shell glob `coder|*-coder)` and regex `^([a-z0-9]+-)?coder$` — both generalising over the whole `<lang>-coder` family. **Consolidating or renaming `coder` breaks `rust-coder`, `cpp-coder` and every future variant in both places at once, and a fix applied to one will not be applied to the other by any grep keyed on a single syntax.**

#### The sweep

Run this for every `TEMPLATE_DELETED` agent name `<N>`:

```sh
# forms 3 + the spawn call: the reference SHAPE, in project-owned prose.
# On the USER-LEVEL pass this arm also matches this skill's own example lines —
# see "Sweep the USER-LEVEL tree too" below for the exclusion and the hand-check
# that replaces it. In the PROJECT tree there is nothing to exclude.
grep -rnE "subagent_type[\"']?[[:space:]]*[:=][[:space:]]*[\"']?<N>\b" . \
     --include='*.md' --include='*.json' --include='*.yaml' --include='*.yml'

# form 1: shell case arms, in every hook on disk.
grep -nE "^[[:space:]]*[A-Za-z0-9_|*?.-]*<N>[A-Za-z0-9_|*?.-]*\)" hooks/*.sh

# form 2: settings.json matcher regexes that MATCH the name. Evaluate the
# regex; do NOT string-compare it to the name — `rust-coder` appears as no
# literal in `^([a-z0-9]+-)?coder$` and is covered only by the generalisation.
grep -o '"matcher": "[^"]*"' .claude/settings.json | sed 's/.*"matcher": "//;s/"$//' \
  | while IFS= read -r m; do printf '%s\n' "<N>" | grep -qE "$m" && echo "matcher: $m"; done

# form 4: agent frontmatter cross-references. EXCLUDE THE AGENT'S OWN FILE —
# `.claude/agents/<N>.md` matches its own `name: <N>` frontmatter, so the file
# being deleted always reports itself as a reference to itself.
grep -rn "\b<N>\b" .claude/agents/*.md | grep -v "^.claude/agents/<N>.md:"

# form 5: hook OUTPUT strings — a live instruction inside a DENY message.
grep -nE "(echo|printf)[^|]*\b<N>\b" hooks/*.sh
```

**`--include` goes BEFORE the paths** — after them it is parsed as another path and the filter silently does nothing. (Same defect class as the placeholder sweep's.)

#### ⚠ FORM 4 SELF-MATCHES, AND THE POLARITY IS THE OPPOSITE OF EVERYTHING ELSE HERE

`grep -l <N> .claude/agents/*.md` includes the file under test, which matches its own `name:` frontmatter. **Every retired agent therefore reports as "still referenced", every time**, and the deletion the sweep exists to authorise is blocked by the sweep itself.

Everything else in this skill fails toward *proceeding*; this one fails toward **refusal — which reads as the safe answer.** A consumer sees the sweep catch something, stops, and concludes it caught something real. It caught the file it was asked about.

> **Uniformity across independent subjects is evidence about the INSTRUMENT, not the subjects.** A consumer's first pass reported **all three** retired agents as still referenced and they looked twice for exactly that reason — *"too tidy; one would have looked plausible."* Three independent agents with independent reference sets do not agree by coincidence. When a sweep answers the same way for every subject, suspect the sweep. `reported-by: penumbra / v3.0.0`

#### The 6d report — PER-FORM, with a probe count from a different source

Report **one line per form per name plus a total**, not a single number:

```
6d name sweep: 5 -> 0 sites across 5 forms x 3 names (15 probes)

  form 1  case arms in hooks         3 -> 0
  form 2  settings.json matchers     0 -> 0
  form 3  subagent_type in prose     0 -> 0
  form 4  agent frontmatter          1 -> 0
  form 5  hook output strings        1 -> 0
```

**`0 -> 0` beats `0 hits`, and is still not enough on its own:** neither distinguishes *ran and found nothing* from *did not run*. The **probe count** is the second number, and it comes from a different source — it is derived from the INPUTS (forms × names), so it cannot go quiet when the search does. Same shape as 6b.1c.

**Per-form is not close to good enough, and the reason is form 3.** A total of 5 proves *a* sweep ran; it does not prove forms 2 and 3 ran, because forms 1, 4 and 5 account for all five hits by themselves. **Form 3 is the form 6d exists for** — the keep-mine `CLAUDE.md` agent-selection table that motivated this whole step is form 3 and nothing else — **and it is the only form carrying `--include` flags**, the defect class that has already landed twice here. A silent form 3 under a nonzero total is a false clean on the exact failure mode.

This is **reporting, not searching**: it adds no greps, so it does not widen the closed set of five forms below. It makes that closed set *visible* instead of an unverifiable claim in prose.

**Report the residual separately — never folded into the delta.** **Weight keep-mine files specially: the sync will not fix those, so a hit there is permanent until a human edits it.**

```
6d name sweep: 5 -> 2 sites across 5 forms x 3 names (15 probes)
  residual, in keep-mine files — PERMANENT until a human edits:
    CLAUDE.md:41   subagent_type: doc-generator     (form 3)
```

**A non-zero residual is the EXPECTED outcome for a consumer with agent routing in keep-mine prose**, not a failed sync. Say so in the report, or the next reader treats a correct result as a red one.

**Acceptance criterion, per pattern language:** enumerate every place a name is bound — case arms, matcher regexes, routing prose, frontmatter, hook output — and **assert the set is unchanged across the consolidation, per pattern language.** A rename then becomes a diff to look at rather than a silence to notice.

#### ⚠ THE FIVE FORMS ARE EXHAUSTIVE BY DESIGN. A SIXTH ARM IS A REGRESSION, NOT EXTRA SAFETY

**Do not add a bare-name grep "just to be sure".** The set of five is closed on purpose: each arm is keyed on a REFERENCE SHAPE, and that keying is the whole mechanism — it is what took 195 hits down to 7 on a real repo. A sixth arm matching the bare name re-imports the 28:1 noise the design exists to eliminate, and the noise does not stay contained: it makes the other five unreadable alongside it, which is how the sweep gets abandoned.

**This is not a hypothetical.** A consumer added a bare-name grep **having just read the 28:1 warning three paragraphs above**, and got 9 benign hits for their trouble. Their own framing is the reason this warning has to be here in its own right:

> *"I was not being careless, I was being thorough."*

**Thoroughness is precisely what the shape-keyed design defends against.** The instinct that adds an arm is the same instinct that produced the 195-hit sweep, and it does not feel like a mistake while you are having it. If you believe a sixth binding form exists, **that is a finding to report, not an arm to add** — a new form changes the table above and belongs in the skill, where the next consumer inherits it.

#### Sweep the USER-LEVEL tree too, on any release that retires a name

The five forms above are scoped to the **project tree**. `~/.claude/` is not in that scope, and **nothing else covers it either**:

- `verify-user-level-drift.sh` compares user-level files against the **released tag**. A user-level file naming a retired agent reports **0 drift**, because the released tag names it too. The probe is working; it is answering a different question.
- The toolkit repo-side censuses scope to `templates/**` and `user-level-reference/**` and do not look for retired names at all.

**Measured, in this skill.** v3.0.0 retired `test-writer` and shipped step 9 still naming it in the list of worktree-isolating agent types — **6d form 3, in the file that defines 6d.** Harmless in effect (an over-broad do-not-spawn list), but it survived a release *because it was outside every sweep, census and drift check at once*. So: **on any release that retires a name, run the same five forms over `~/.claude/` and over the toolkit's own `user-level-reference/` and `docs/`**, and report that pass separately.

**The sweep's own example lines are not sites — and the exclusion has a catch.** Run over `~/.claude`, form 3 matches the example lines in `skills/sync-template/SKILL.md` itself: one phantom site on every run, measured by a consumer. Add `--exclude-dir=sync-template` to the form-3 arm for the user-level pass **and then read this file by hand for the retired name** — because the one real user-level hit anybody has measured (`test-writer`, above) was *in this file*. A blanket exclusion alone would have hidden exactly the defect that motivated the section. Excluded-then-hand-checked, never excluded-and-forgotten; say which of the two you did in the report.

> **CONSTRAINT THIS PUTS ON ANY CONSOLIDATION: ABSORB, DO NOT RENAME.** Both the matcher regex and the skills case arm already generalise over the variant family, so superset-under-an-existing-name is compatible **only while the surviving name is `coder`**. If a consolidation renames rather than absorbs, all three binding sites break silently at the same moment. With an existing name, a stale reference in a consumer's keep-mine prose fails loudly at spawn, which is recoverable; with a new name, every consumer's prose is stale at once.

### 7. Finalize

Call `template_finalize_sync(project_path=".", applied_files=<JSON array of all template_apply_file results>)`.

**Re-register keep-mine files LAST** — every `source="skip"` registration is the last action before finalize, after every edit including the sync's own write-up into `PROJECT_STATE.md`. A hash recorded before a later edit describes nothing, and on a file with a live PROJECT-CUSTOM region those stale part hashes are exactly what the next sync's classification reads.

**Act on the predates-part-hash hint (v2.2.4, consumer feedback).** When `template_compute_status` marks a file with the hint that its manifest entry predates part hashes ("re-register to get region-aware classification"), that file goes in this sync's `source="skip"` set — re-registered last, with the keep-mine files above. Until it is, the server cannot tell region content from real deviation and has to report the file as deviating. Measured on a consumer repo: after re-registration `CLAUDE.md` came back with `localPartHash == templatePartHashAtSync`, reclassified `region_only: true, deviates_from_template: false`, and the deviating count dropped 4 → 3 — the honest number, because that file does not deviate from the template, it only carries region content. Do not leave the hint for the next sync; it is emitted precisely because this sync can clear it. **If no entry carries a hint, there is nothing to do here** — this clause exists for manifests that predate the part-hash fields, and a recently-synced repo has already re-registered everything (measured: `hint: ""` on all 36 entries of one consumer). An empty hint set is the healthy state, not a missing step.

Build `applied_files` PROGRAMMATICALLY from the collected `template_apply_file` results only — never hand-assemble or re-type entries (hand-typed hashes have silently corrupted a manifest; the server now rejects malformed hashes, but the discipline stands).

**Shape this as two short commands, not one long one.** Write the `applied_files` JSON — and any validator — to the scratchpad with the Write tool, then run `python3 <validator-path> <json-path>`. The payload will always contain hook paths (`hooks/run-gate.sh` among them, by construction), and a long command line carrying them is the shape that has repeatedly tripped a guard: it is also the standing "move logic into a script file" rule, arriving from a third direction.

**Do NOT gate finalize on a client-side re-hash** (removed in v2.2.4, consumer feedback). Earlier versions of this step required recomputing each entry's hash from disk and asserting it matched `localHash`. That is not implementable from the skill text as written, and the file it reddens first is `PROJECT_CONTEXT.md` — the one file this skill's own conflict guidance says every consumer must splice. Both honest responses to that red are bad: finalize anyway (and learn to ignore a guard), or stop a clean sync. The original hand-typed-hash incident is already covered server-side — `template_finalize_sync` rejects malformed hashes — and by the "build `applied_files` programmatically" rule above.

*Optional diagnostic, never a gate.* If you do want to compare a hash by hand, `localHash` is sha256 over the file read as Python text (`path.read_text(encoding="utf-8")`, i.e. **universal newlines**: CRLF and CR both become LF) with a **leading BOM stripped**, re-encoded UTF-8 with the BOM stripped again. A raw sha256 of the bytes on disk disagrees with it on any CRLF file and on any file carrying a BOM — a consumer ruled out raw sha256, newline normalisation, whitespace stripping and placeholder reversal in all six permutations before the BOM turned out to be the difference. A mismatch here is evidence about *your* reimplementation first, not about the manifest.

**Post-finalize self-check:** re-run `template_compute_status(project_path=".")`. A clean sync shows `auto_update: 0, conflict: 0`. Anything else means the manifest was corrupted during finalize — report it to the user instead of finishing.

**Post-apply placeholder sweep (MANDATORY).** One grep over the applied set, before the report.

**Run the three arms below verbatim; do not invent a broader regex.** The placeholder shape this toolkit ships is `{{[A-Z_]{2,}}}` and nothing else. A consumer widened it to `__[A-Z_]{3,}__` and got 38 false hits in one sweep — that shape is every MCP tool name (`mcp__MCP_DOCKER__…`), not a placeholder. A sweep that cries wolf 38 times is a sweep the next person skips.

```
# The markdown and shell arms are BOM-tolerant: a UTF-8 BOM sits at byte 0,
# INSIDE line 1, so an unprefixed `^` stops matching a key at the top of the
# file. See below. The JSON arm needs no BOM handling — it has neither a `^`
# anchor nor a comment filter, which are the only two things a BOM breaks.
BOM=$(printf '\357\273\277')
# markdown: only a config-VALUE line, which is where a placeholder is load-bearing
grep -rn -- "^\(${BOM}\)\?[-*[:space:]]*\*\*[^*]\+\*\*:.*{{[A-Z_]\{2,\}}}" .claude *.md
# shell: skip comment lines — prose ABOUT a placeholder is not a placeholder.
# OPTIONS BEFORE PATHS: `--include` after the paths is parsed as another PATH.
# NO `2>/dev/null` on ANY arm — the sweep's stderr is deliberately
# unsuppressed; it is the only thing that reports a malformed invocation.
# PIPEFAIL: without it `$?` is the LAST grep's status and the first one's 2
# (a malformed invocation) is invisible to anything testing the exit code.
# SCOPED TO A SUBSHELL, deliberately — see the exit contract below.
( set -o pipefail
grep -rn --include='*.sh' -- '{{[A-Z_]\{2,\}}}' .claude hooks | grep -v ":[0-9]*:\(${BOM}\)\?[[:space:]]*#"
)
sweep_rc=$?
# json: TRACKED files only, never a filesystem walk. `.claude/settings.json` is
# template-tracked, substituted at apply time, and composed almost entirely of
# hook `command` strings — an EXECUTABLE position, so a literal {{...}} there is
# a path that does not resolve, i.e. 127, i.e. fail-open.
# NO exclusions and NO shape requirement, deliberately: JSON has no comments, so
# any {{...}} in a .json file is in a VALUE by construction. Do not add a
# comment filter by analogy with the shell arm; there is nothing to filter.
# `git grep`, NOT `git ls-files … | xargs grep`: xargs maps ANY grep exit in
# 1..125 to its own 123, collapsing "clean" and "malformed" — the very
# distinction pipefail was added to expose (measured: xargs 123 both ways).
# git grep needs no pipeline, cannot wander into .venv or build output, and
# handles spaces in paths.
git grep -n -e '{{[A-Z_]\{2,\}}}' -- '*.json'
json_rc=$?     # 0 = hits (a PROBLEM), 1 = clean, 128 = malformed (NOT grep's 2)
```

**THE SWEEP'S EXIT CONTRACT — SUCCESS IS 1 AND FAILURE IS 0 (v2.2.5 round 4).** `pipefail` is correct and does its job, but the resulting contract is inverted relative to every instinct, and nothing said so:

```
exit 0  ->  hits found              a PROBLEM: unfilled placeholders, report them
exit 1  ->  clean, no hits          SUCCESS — this is grep's no-match, not an error
exit 2  ->  malformed invocation    the defect pipefail was added to expose
```

**The JSON arm keeps 0-and-1 and reports malformed as 128, not 2** — that is `git grep`'s convention, not `grep`'s, and it is the reason the arm is `git grep` rather than a `git ls-files | xargs grep` pipeline: xargs would return **123** for both the clean case and the malformed one. So the testable form is *"0 means hits, 1 means clean, anything else means broken"*, which holds for all three arms; only the literal `2` is grep-specific.

**Check for a non-{0,1} code; non-zero alone is not an error.** Two consequences follow directly, and both have already been written by someone reading this file:

- `if ! sweep; then fail` marks **every clean tree** as broken.
- This skill mandates putting logic in a **script file**, and `set -o pipefail` is typed as `set -euo pipefail` from muscle memory — under `set -e` a **clean sweep aborts the script**, turning the correct outcome into a hard stop with no message.

**And scope `pipefail`.** As a bare `set -o pipefail` it leaks into the rest of the hosting script and changes the exit semantics of every later pipeline there. The subshell above contains it; `( set -o pipefail; … )` or an explicit save/restore both work, and the subshell is one character cheaper to get right.

**THE JSON ARM IS NOT REDUNDANT WITH THE TOOLKIT'S OWN SHIPPING CENSUS — DO NOT DELETE IT AS OVERLAPPING (v2.2.5 round 7).** `scripts/verify-template-consistency.sh` runs a repo-side JSON census over `templates/**` and `user-level-reference/**`, so it is tempting to read this arm as the same check one tree over. It is not, and the asymmetry cuts the OPPOSITE way to the usual one:

| tree | repo-side census | consumer-side arm (here) |
|---|---|---|
| user level | **sufficient**, because the user-level install is *verbatim* — nothing substitutes there | not needed, and this arm deliberately never touches `$HOME` |
| project | **necessary, NOT sufficient** — the project install is *not* verbatim | **the only detector for the install-introduced class** |

The project bootstrap substitutes, and substitution is exactly where a placeholder survives: per the rule below, `template_apply_file` substitutes only placeholders present in **the project's** manifest, so a key the manifest predates lands as a literal in the consumer's file while the template it came from is perfectly clean. **That is v2.2.0's chain verbatim — template correct → substitution incomplete → the consumer carries `- **Protected branches**: {{DEFAULT_BRANCH}}` → trunk silently unprotected — with a template-side census green throughout.** It was an *install* defect, not a shipping defect, and only a consumer-side check can see it. Today the JSON exposure is latent (no `*.json` under `templates/` carries a placeholder, so substitution is a no-op for JSON); it appears the first time someone adds one, in a file full of executable command strings, with the shipping census still green.

**`git grep` reads the WORKING TREE for tracked files, which is the moment this sweep runs in** — verified: a tracked `settings.json` edited but neither staged nor committed is still found (rc 0). It has to be, because the sweep runs immediately after `template_apply_file` and before anything is committed. **Named residual, from the same property:** a file the sync *creates* for the first time and that nobody has `git add`-ed yet is untracked, so this arm cannot see it. That is the same scoping that keeps the arm out of `.venv` and out of another tool's backups, and it is the right trade — but in a brand-new project with nothing committed, run the sweep again after the first `git add`.

**Scope by OWNERSHIP, never by key name, and expect the two ends to look different.** This arm scopes with `git ls-files` (tracked files); the repo-side census cannot use git for its user-level half and scopes by directory instead. **They are asymmetric in construction though symmetric in intent** — do not "harmonise" them into one filesystem walk. A walk over `~/.claude` was measured at 3430 JSON files with one hit, in a dated backup carrying *another tool's* placeholder keys: red on day one for a benign reason, which is how a guard gets disabled by someone whose reasoning looks sound. And do **not** narrow either end by filtering on known toolkit key names: that rots the first time a key is added, and it would hide a genuine unfilled placeholder under the new one. Scope is the right axis; the key set is not.

**Why the `${BOM}` in the markdown and shell arms (v2.2.4).** PowerShell 5.1's `>` and `Out-File` write UTF-8 **with** a BOM, and a consumer's `PROJECT_CONTEXT.md` was found carrying one — this is a live Windows shape, not a hypothetical. The two arms fail in opposite directions and both are wrong: arm 1's `^` no longer abuts the key, so **a placeholder on line 1 behind a BOM is a FALSE CLEAN** — the sweep's whole job, missed silently, on the case a consumer reordering their file most plausibly creates. Arm 2's exclusion filter is the mirror: the BOM lands between the `:` and the `#`, so a BOM'd comment stops being recognised as a comment and comes back as a **false positive**. Measured on a fixture, before → after: arm 1 line 1 `0 → 1`, line 2 `1 → 1`, no-BOM control `1 → 1`; arm 2 BOM'd comment `1 → 0` false positives. Same class as the hook extractors' `GC_KEY_PRE` — the server strips the BOM for hashing and a `^`-anchored grep does not, so the same file is two different files depending on which one is looking.

**Why the option ordering is load-bearing, and why the stderr stays visible (v2.2.5).** Until this release arm 2 read `grep -rn -- '…' .claude hooks --include='*.sh'`, with the option AFTER the paths — where `grep` parses it as another **path**, not an option. So the `*.sh` restriction never applied at all: arm 2 recursed every file under `.claude` and `hooks`, and its comment filter — correct for shell, wrong for markdown — then **silently ate a genuine markdown placeholder**, because `# {{FOO}}` reads as a comment line. Measured on GNU grep 3.0 (Git Bash / Windows), planted fixture of `conf.json`, `doc.md` (line 1 `# {{FOO_BAR}}`) and `s.sh`, and reproduced independently by a consumer:

```
SHIPPED (options after paths):   conf.json, doc.md, s.sh   filter inert, every type matched
                     stderr:     grep: --include=*.sh: No such file or directory
CORRECTED (options first):       s.sh                      correct
SHIPPED + comment filter:        conf.json, s.sh           <- doc.md's "# {{FOO_BAR}}" DROPPED
CORRECTED + comment filter:      s.sh                      correct
```

That third row is the sweep failing at its entire job, quietly — the same shape as the BOM false-clean the v2.2.4 arms were written to prevent. Options before paths is unambiguous everywhere; `scripts/verify-template-consistency.sh` pins the ordering so it cannot drift back.

**Keeping stderr visible is necessary but NOT sufficient — the exit code hides too (v2.2.5).** A malformed `grep` invocation exits **2**, but arm 2 is a pipeline, so a bare `$?` is the *last* grep's status: the 2 never surfaces and anyone wrapping the sweep in a script that tests its result gets a clean-looking answer even with stderr unsuppressed. `set -o pipefail` (above) or an explicit `${PIPESTATUS[0]}` check is what makes the failure testable; without one the defect recurs the moment someone automates the sweep. Stderr caught it for a human; the exit code is what catches it for a script.

**Placeholders inside FENCED CODE BLOCKS are OUT OF SCOPE — decided, not omitted (v2.2.5).** A reviewer scanning unfiltered found a consumer's `CLAUDE.md` carrying `{{BUILD_COMMAND}}`, `{{TEST_COMMAND}}` and `{{FORMAT_COMMAND}}` unfilled inside its Quick Start fenced block. No arm sees them: the markdown arm requires a `- **Key**: value` line, the shell arm requires `*.sh`, the JSON arm requires `*.json`. **That is deliberate and stays.** Two reasons. First, the same one that narrowed arm 1 in the first place — a pattern broad enough to reach fenced blocks flags the toolkit's own *documentation* of placeholder handling, including the sweep's own source above and every template's Quick Start, and the better the handling is documented the noisier its own detector becomes. Second, the failure this sweep exists for is a config value that reads as data to a *tool*: v2.2.0's `- **Protected branches**: {{DEFAULT_BRANCH}}` silently unprotected trunk. A fenced snippet telling a human what to type is read by a human, who has the surrounding sentence — in the reported case, the file's own "Replace placeholders above with your project's actual commands." **Named residual gap:** an unfilled placeholder in a fenced block is not reported, so a project that never followed that instruction will not hear about it here. The fact that would flip this decision is a fenced-block placeholder that some *tool* parses; there is not one today.

**Do NOT add `2>/dev/null` to any arm.** The `No such file or directory` above is the *only* signal a malformed invocation gives, and it is the one a consumer running the line literally would have seen — this defect went unnoticed for a release because the reporting consumer had wrapped the shipped line in `2>/dev/null` in their own script. After the ordering fix that particular error is gone anyway; the principle is for whatever the next mistake is. A guard whose diagnostic is suppressed is not a guard.

**Why not the plain `grep -rn '{{[A-Z_]\{2,\}}}' .claude hooks *.md`:** it flags the toolkit's own documentation of placeholder handling — `hooks/lib/git-cmd.sh`'s comments explaining the `{{DEFAULT_BRANCH}}` arms, and `hooks/pre-commit-test.sh`'s comment naming `{{TEST_COMMAND}}`. Every consumer hits those three lines and has to reason them out, and the better the handling is documented the noisier its own detector becomes. Reported independently by two consumers. **Do not fix it by excluding `hooks/lib/` by name** — that rots on the first rename and would hide a genuine unfilled placeholder in a hook script. Excluding *comment lines* and requiring markdown hits on a `- **Key**: value` line kills all three false positives and keeps every real one. Verify the refinement the same way it was verified upstream: the sweep must report zero on a clean tree, and must still catch a placeholder planted in a `- **Key**:` line — **on line 1 behind a BOM as well as further down**, which is the pair the v2.2.4 arms above exist for.

Any hit is a file the template wrote with an unfilled placeholder — `template_apply_file` substitutes only placeholders present in the project's manifest, so a key the manifest predates (`DEFAULT_BRANCH`, `GATE_COMMAND`, `WORKTREE_BASE`, `LOG_PATH`) lands as a literal on **both** accept-template and accept-merged. Fill it or delete the line; list every hit under `Warnings:` either way. This one grep is what stands between a consumer and a config value that reads as data — v2.2.0 shipped `- **Protected branches**: {{DEFAULT_BRANCH}}`, and until v2.2.1's resolver fix that literal silently unprotected trunk.

### 7b. Stamp the Version Fields into the Manifest (v2.2.5)

`lastSynced` is a **commit sha**, and nothing else in a synced repo carries a version marker. So "which toolkit version is this repo on?" currently needs the toolkit checkout present *and* its tags fetched. Measured across four live consumers, every one of them was an opaque hex string. Two additive manifest fields fix that:

| Field | Value | Written by |
|---|---|---|
| `lastSyncedVersion` | the toolkit tag for `lastSynced` | **this skill** (client-side, DERIVED — recomputed on every sync) |
| `lastSyncedVersionOf` | the `lastSynced` sha `lastSyncedVersion` was computed from | **this skill** — the staleness backstop; see rule 2b |
| `templateSyncToolsVersion` | the `template-sync-tools` version that performed the sync | **the server**, when it starts emitting a version — this skill never guesses it |

**Both are optional labels. NEVER fail, block or roll back a sync over either one** — an unresolvable version is a missing label, not an error. Absent means *unknown*, never *stale*: every pre-v2.2.5 manifest stays valid unchanged.

**Resolve `lastSyncedVersion`** against the manifest's own `templateRepo` and `lastSynced`, in this order — first one that succeeds wins:

```
git -C <templateRepo> describe --tags --exact-match <lastSynced>   # v2.2.5
git -C <templateRepo> describe --tags <lastSynced>                 # v2.2.4-3-gabc1234
#                     ^^^^^^^^^^^^ NO --abbrev=0, DELIBERATELY. With it the
#   fallback returns the nearest ANCESTOR tag — a bare `v2.2.4` for a commit
#   strictly NEWER than v2.2.4 — so the manifest would record a version OLDER
#   than the one actually applied, with no error and no empty string. `""` is
#   honest: it is unknown announcing itself. A bare ancestor tag is confidently
#   wrong, and it fires on exactly the consumers who sync off-tag to pick up a
#   fix early. The `-3-gabc1234` suffix is the signal, not noise; do not tidy it.
```

**Checking a `lastSynced` against a tag needs `^{commit}` — TAG TYPE VARIES, so ALWAYS DEREF (v2.2.6, corrected v3.0.1).** On an *annotated* tag, the tag name resolves to the **tag object's** sha, not the commit's:

```
git rev-parse v2.2.5            -> 300020f     <- the TAG OBJECT. Never equals lastSynced.
git rev-parse v2.2.5^{commit}   -> 640ba5e     <- the commit. This is what lastSynced holds.
```

> **Do NOT rely on "toolkit releases are annotated" — that claim was in this file and it is false.** The tag type depends on **how the release was cut**: `git tag -a` (and `git tag -s`) creates an **annotated** tag with its own object; a release cut through the **GitHub API** — including the GitHub MCP release tools this repo's own guidance prefers — creates a **LIGHTWEIGHT** tag, which is a plain ref straight to the commit. **v2.3.0 is lightweight for exactly that reason.** The cause is stated here rather than left out because without it the next releaser has no way to know which kind they are about to make.
>
> `^{commit}` is a no-op on a lightweight tag and the correction on an annotated one, so **deref unconditionally and never branch on the type.** A rule of the form "these are annotated, so deref" rots the first time someone cuts one the other way — which has already happened.

Anyone verifying a consumer's `lastSynced` against the tag without `^{commit}` reports a **false mismatch** and goes hunting a sync bug that does not exist. `describe --tags` above is unaffected (it takes a commit and returns a name), and `verify-user-level-drift.sh` already derefs correctly — this is a rule for the humans and release notes doing the comparison by hand.

**Distinguish the ways this can fail to resolve — an opaque `""` reproduces, one level down, the opaque `lastSynced` this whole step exists to fix (v2.2.5).** Four distinct outcomes, four distinct values:

| state | value written | how to read it |
|---|---|---|
| resolved to a tag | `"v2.2.5"` | exact; `--exact-match` succeeded |
| untagged but resolvable | `"v2.2.4-3-gabc1234"` | three commits past v2.2.4 — a real, precise answer, not a failure |
| no toolkit checkout reachable | `"unknown:no-checkout"` | `templateRepo` is absent, or `git -C` cannot open it |
| checkout present, no tags | `"unknown:no-tags"` | fetch tags (`git fetch --tags`) and re-run to label it |
| this skill never ran | key **ABSENT** | a pre-v2.2.5 manifest; absent means unknown, never stale |

Never write a bare `""` — it is indistinguishable from "resolved, to nothing". The bounded shape of the failure, measured: on a host with the toolkit checked out and its 18 tags fetched, `--exact-match` resolves correctly, so the unresolved states are specific to **no checkout, a shallow clone, or a fetch without tags** — a bounded defect, not an open-ended one.

**Control, both arms, and assert the untagged arm POSITIVELY.** A tagged HEAD must resolve to the exact tag; an **untagged** HEAD must produce a value matching `-g[0-9a-f]{7,}`, i.e. it *carries the describe suffix*. Do **not** phrase the second as "is not an ancestor tag": that is awkward to express and passes **vacuously** on an empty string, a malformed value, or a swallowed exception — a fixture with the shape of a failing-arm test whose failing arm can go green for reasons unrelated to the guarantee. "Carries the suffix" is one positive assertion that an `--abbrev=0` refactor breaks on its first run, which is the named regression actually being guarded.

> **SELECT THE UNTAGGED COMMIT BY THE PROPERTY, NEVER BY POSITION — and assert the fixture HAS the property before concluding anything (v2.2.6; hit independently by three consumers, one of whom "nearly reported your implementation as broken").** Arm 2 needs an untagged commit and this step never said how to find one, so the obvious `<release-sha>~1` gets used. On a well-tagged repo — i.e. this one — the previous commit is very often **the previous release**: `640ba5e~1` is `d67b507`, itself tagged `v2.2.4`, so `describe --tags` correctly returns a bare tag and the arm reports FAIL. **That failure is indistinguishable from the `--abbrev=0` regression the arm exists to catch**, and the tempting next move is to "fix" the resolver, which is working.
>
> ```sh
> # Walk back until describe --exact-match FAILS; that commit is untagged BY MEASUREMENT.
> c=$(git -C <templateRepo> rev-parse HEAD)
> while git -C <templateRepo> describe --tags --exact-match "$c" >/dev/null 2>&1; do
>   c=$(git -C <templateRepo> rev-parse "$c~1")
> done
> # assert the fixture's property FIRST, then the implementation's behaviour:
> git -C <templateRepo> describe --tags --exact-match "$c" >/dev/null 2>&1 && { echo "FIXTURE INVALID: $c is tagged"; exit 1; }
> git -C <templateRepo> describe --tags "$c" | grep -Eq -- '-g[0-9a-f]{7,}' || { echo "arm2 FAIL"; exit 1; }
> ```
>
> **The general rule, which outlives this arm: a control must assert its own fixture carries the property under test, or the control's failure cannot be told from the regression it guards.** Position is provenance; taggedness is the property. Bites hardest on the repos that tag most carefully.

**Run those through the Bash tool, not from inside the stamping script.** Consumer manifests store `templateRepo` as an MSYS path (`/g/git/claude-code-toolkit` in all four measured) and native `git.exe` spawned from Python cannot resolve it — it exits non-zero, both fallbacks "fail", and the label silently comes out `""` on a repo whose tags are right there. Measured: same sha, same repo, `''` from a Python `subprocess` versus `v2.2.3` from Bash. Resolve the string in Bash, hand it to the script.

**Do NOT invent `templateSyncToolsVersion`.** Write it only from a version the *server itself* reports in a `template_*` response. As of `template-sync-tools` 0.2.x no response carries one — which is the underlying complaint: a consumer found on 0.1.0 this week could only discover it by describing a symptom. Until the server emits one, leave the key **absent** and report `Sync server: unknown` (see step 8). A user-typed or inferred number in a server-owned file is worse than no field at all, because the next reader cannot tell it apart from an authoritative one.

**How to write them, mechanically:**

1. **After** `template_finalize_sync` and after the post-finalize self-check — finalize rewrites the manifest, so a stamp applied before it is discarded.
2. **Never-clobber, and it does NOT apply to a DERIVED field (v2.2.5 round 4).** The rule is: *only write a key that is absent or empty* — a future server that writes these fields authoritatively must win, and the client never clobbers a value it did not write.

   **Never-clobber exists to protect values the client cannot REPRODUCE** — server-authoritative data, hand-edited resolutions, anything where overwriting destroys information that cannot be recovered. **A derived field is by definition reproducible**, so it is not in the class the rule protects, and applying the rule to it converts *"do not destroy information"* into *"preserve a wrong answer"*.

   **The corollary is the actionable half, and it covers every future field of this shape:**

   > **A derived field is rewritten with its source, or not at all. If `lastSynced` changes, everything computed from it is recomputed in the same write.**

   So `lastSyncedVersion` — a pure function of `templateRepo` + `lastSynced`, and `lastSynced` changes on every sync — is **recomputed and overwritten every time, unconditionally**. Never-clobber applies **solely** to `templateSyncToolsVersion`, for the stated reason (the client cannot observe it), not because it appears on a list of exceptions. Written as a class exclusion deliberately: a named exemption for `lastSyncedVersion` is something a future editor can fail to extend to the next derived field, and the trap would be re-set silently.

   **Why this is not a tidy-up: a stale version label is WORSE than an absent one.** Absent reads as *unknown* and sends the reader to the sha. Stale reads as *authoritative* and answers *"do I have the fix?"* **wrongly** — the exact question this step was opened to answer, failing hardest on the consumers who sync most often. Under the old wording there was no third case: if `template_finalize_sync` preserves the key, every subsequent sync leaves a confidently-wrong label; if it drops it, the rule was dead code for this field. Harmful or vacuous.

2b. **Backstop, for when the exclusion is forgotten: store what the label was computed FROM.** A version label that cannot be checked against the thing it labels is itself a value that needs provenance. Write `lastSyncedVersionOf` beside it, carrying the `lastSynced` sha the label was derived from:

   ```json
     "lastSynced": "707052c",
     "lastSyncedVersion": "v2.2.3",
     "lastSyncedVersionOf": "707052c",
   ```

   A reader then compares the two: **equal means the label is good; unequal means it is stale AND KNOWN STALE.** That converts a confidently wrong answer into a detectable one, which is the whole difference this step exists to deliver. Step 8 reports `{lastSyncedVersion} (stale — computed for {lastSyncedVersionOf}, manifest is at {lastSynced})` when they disagree, and the two unresolved-state values (`unknown:no-checkout`, `unknown:no-tags`) are written with the same companion key so the pairing has no gaps. The fifth table row — key **ABSENT** — has no value to pair and takes no companion key.
3. Write with the Write tool + a scratchpad script (`json.load` / `json.dump`), never by hand-editing the JSON and never by a long `python -c` command line — the same rule as `applied_files` in step 7. Preserve `indent=2`, LF endings, no BOM, and `ensure_ascii=False`.

   **REBUILD the top-level mapping in the documented order — do NOT assign into the loaded one (v2.2.6).** Python dicts are insertion-ordered and `json.dump` follows, so the natural `m = json.load(...); m["lastSyncedVersion"] = …; json.dump(m, …)` **appends** both keys after every pre-existing key. Measured on a consumer manifest: `lastSynced` landed at line 5 and its two labels at lines **276-277**, past the entire `files` map, **270 lines from the field they annotate**.

   That is not cosmetic *in this step's own terms*. 7b exists so a human can read the version **without opening the toolkit**. Below the `files` map, a reader checking the header sees a bare sha and concludes the version was never stamped — which is exactly what one consumer's user did, and they were right to. **The feature is the visibility; the placement is the feature.**

   The documented top-level order, which is also the order the docs table lists:

   ```
   version, variant, templateRepo, lastSynced, lastSyncedVersion, lastSyncedVersionOf,
   templateSyncToolsVersion (when present), placeholders, files
   ```

   ```python
   ORDER = ["version", "variant", "templateRepo", "lastSynced",
            "lastSyncedVersion", "lastSyncedVersionOf",
            "templateSyncToolsVersion", "placeholders", "files"]
   out = {k: m[k] for k in ORDER if k in m}
   out.update({k: v for k, v in m.items() if k not in out})   # unknown keys survive, at the end
   ```

   The `update` line is required, not tidy: `template_finalize_sync` mutates and re-dumps the RAW manifest, so **unknown top-level keys are preserved** (measured with a planted canary). Dropping them here would destroy data the server deliberately keeps.

3b. **Assert POSITION, not presence — every existing check in this step is blind to it (v2.2.6).** After writing, `template_compute_status` is clean, `template_load_manifest` is valid, and a `json.load` key check is green — **all three read BY KEY**, so all three pass with the labels 270 lines out of place. The step's own verification is structurally incapable of catching the one thing the step is for.

   ```python
   assert list(manifest)[:6] == ["version", "variant", "templateRepo",
                                 "lastSynced", "lastSyncedVersion", "lastSyncedVersionOf"], list(manifest)[:6]
   ```

   A pre-v2 manifest that carries `version` last is the one legitimate exception — the v1→v2 migration appends it by assignment and no sync has ever corrected it. Report that as `manifest key order: pre-v2 shape (version last)` rather than failing; it is a server-side fix, not something to hand-repair here.

4. Re-run `template_compute_status` afterwards; it must still be clean. If the stamp upset anything, revert the two keys and report — the sync is still good, the label is not worth a corrupt manifest.
5. `.claude/template-manifest.json` is already in the step-9 `git add`, so nothing extra to stage.

Before → after, on a real consumer manifest — **note where the two new keys sit**: immediately after the field they annotate, in the header, not appended at the end of the file:

```json
  "templateRepo": "/g/git/claude-code-toolkit",
  "lastSynced": "707052c",
+ "lastSyncedVersion": "v2.2.3",
+ "lastSyncedVersionOf": "707052c",
  "placeholders": { ... },
  "files": { ... }
```

A consumer re-ordered their own manifest to this shape as a pure move: parsed content identical, byte count identical, 3 insertions / 3 deletions, every entry still valid.

**Provenance, say it out loud when asked:** `lastSyncedVersion` is *client-written by this skill*, derived from the same `templateRepo` + `lastSynced` the server wrote, so it is reproducible and checkable — but it is not server-authoritative, and a repo synced by an older skill will not have it.

### 8. Report

Then run `bash <toolkit>/scripts/verify-user-level-drift.sh` and fold its result into the report as one line. **It compares against the last RELEASED tag, not the working tree** (v2.2.5 round 4): a live `~/.claude/` matching an unshipped branch used to report 0 drift, so the delivery probe certified that an unreviewed revision had reached a user. Reference files that exist only on a branch are listed as `UNRELEASED`, never counted as in-sync.

**If it exits 2 with `cannot resolve a released reference`, fold that into the report as `User-level: drift not checked (no released reference)` and CARRY ON.** A shallow clone or a fetch without tags is a measured consumer state, and this step is a probe, not a gate — the same rule as step 7b's version labels: an unresolvable version is a missing label, never a reason to fail or roll back a sync. **Do not silently retry with `--worktree`**: that reinstates the comparison that reports 0 drift against an unshipped branch, which is the failure the released-tag default exists to close. Say it was not checked.

**DEFINITION OF DONE FOR A USER-LEVEL FILE IS RESTART-REQUIRED, NOT RE-COPY (v2.2.5 round 4).** Copying `SKILL.md` into `~/.claude/skills/` changes nothing for any session already running — including this one. The report has told users *"Restart before relying on changed agent definitions or skills"* for several versions; **the skill knew this about agents and not about itself.** So when this sync changed a user-level skill or agent, the delivery step is not complete until the session is restarted, and the report says so with the file named. Anyone mid-session while a copy is installed is running the previous version's steps against the new manifest.

Re-run the step-3 **positive control** here as well (the same temp script, `bash <path>`) and fold its result in: the sync rewrote `hooks/` and `settings.json` since the first probe, so this is the run that tells you the *post-sync* enforcement layer is live. `exit=2` + `BLOCKED` → report `Gates: live (scripts behave correctly on a fed payload)`. `exit=0` → report `Gates: INERT` and the recovery note, not a clean sync. Keep the parenthetical: the probe feeds the payload itself, so `live` here means the scripts work, never that the harness fires them.

**Name the parser AND its consequence on the `Gates:` line.** The hooks pick the first WORKING backend of node → python3 → jq, and six of them (`read-size-gate`, `bash-output-guard`, `enforce-delegation`, `retro-ledger`, `retro-brief`, `enforce-agent-contract`'s transcript scan) are embedded node programs that stay inactive without node specifically. "Live" alone hides that. Field-validated shape, use it verbatim:

```
Gates:        live (parser: node — all 12 hooks enforcing)
Gates:        live (parser: python3 — 6 node-only hooks inactive)
```

**Probing the MERGE gate from inside a guarded session blocks itself — and that block IS the positive result.** A probe command that builds a payload containing the literal `git merge` is matched by the real PreToolUse hook on the echo that constructs it, not on any merge. That is the unanchored matcher doing its documented job (these gates are fail-CLOSED; false positives are the accepted price of not being fooled by `bash -c "…"` wrapper forms). So: do not treat a self-block as a broken probe, and do not synthesise a payload to "really" test it — a real command, really blocked, with real shas in the message is the better proof. Where a synthetic probe genuinely is needed, drive the script from **outside** the session, never inline in a command string.

The FIRST line of the report is this sentence, verbatim:

```
Gates are live immediately (settings.json hot-reloads). Restart before relying on changed agent definitions or skills.

Sync complete: {variant} @ {new_commit}

  Auto-updated: [list]
  Merged:       [list]
  Spliced:      [list — files where template and local content were combined by hand]
  Skipped:      [list]
  New files:    [list]
  Warnings:     [list — every placeholder-sweep hit belongs here]
  User-level:   [one-line verify-user-level-drift.sh summary]
  Gates:        live (parser: {backend} — {consequence})
  Toolkit:      {lastSyncedVersion} ({lastSynced})
                [when lastSyncedVersionOf != lastSynced: "STALE LABEL — computed
                 for {lastSyncedVersionOf}; read the sha, not the version"]
  SKILL body:   {the version marker at the top of this file, as LOADED}
  Sync server:  {templateSyncToolsVersion}
  Backup:       {step-2b directory, ABSOLUTE and RESOLVED} [{gitignored tracked files copied}]
```

`Backup:` prints `os.path.realpath(...)` of the directory that was actually written — never `/tmp/...` and never the `${TMPDIR:-/tmp}` expression. On Windows the two differ and the reported one does not exist (step 2b).

`Toolkit:` and `Sync server:` (v2.2.5) exist so a human sees both versions without opening the manifest — the whole point of step 7b. Print what step 7b resolved, and print the honest shape when it resolved nothing:

```
Toolkit:      v2.2.5 (d67b507)
Toolkit:      v2.2.4-3-gabc1234 (abc1234) — untagged commit, three past v2.2.4
Toolkit:      unknown:no-tags (abc1234) — checkout present but no tags; `git fetch --tags` and re-run to label it
Toolkit:      unknown:no-checkout (abc1234) — no toolkit checkout reachable at the manifest's templateRepo
Toolkit:      (field absent) — synced by a pre-v2.2.5 skill; unknown, not stale
Sync server:  unknown (server reports no version — client never guesses it)
```

`Spliced:` is its own category on purpose: the conflict guidance now recommends splicing over accept-template for files that carry project values, and a spliced file is neither auto-updated nor merged by the server. Reporting it as "Skipped" hides work that was actually done.

### 9. Commit the Sync

Commit the synced tree yourself, from the main thread — `git add`/`git commit` here are the PO's documented git-I/O role for this skill, not hands-on coding (`AGENT_TEAM.md`: agents without a usable tree return work; the PO commits). **Never spawn a worktree-isolated agent to commit a sync.** `coder`, `*-coder` and `tester` all set `isolation: worktree`; the harness creates that worktree from `main`, whose `hooks/` predate the sync, while the session's hot-reloaded `settings.json` already fires the v2 gates on every Bash call — the result is every Bash call in that worktree blocked ("BLOCKED: Tests failed…" even for `ls`). If you must delegate this step, use `ops` or `general-purpose` (neither sets `isolation: worktree`).

Before `git add`/`git commit`: run `git diff CLAUDE.md` and check for a re-appended `# context-mode — MANDATORY routing rules` block. The context-mode plugin re-appends this block after `PROJECT-CUSTOM:END` on every session start, so a CLAUDE.md cleaned earlier in the sync is dirty again by the time you commit. Remove the re-appended block (or disable the plugin) before staging, otherwise the commit silently reintroduces it.

Match the plugin's **heading**, not the phrase: `grep -c '^# context-mode' CLAUDE.md` must be `0`. The template's own text mentions "context-mode" by design (the sentinel section under `## context-mode plugin`), so a substring grep reports a false positive on a perfectly clean file; only a line *starting* `# context-mode` is the re-appended plugin block.

Stage exactly the sync's touched files — the list is already in hand: every `applied_files` result from step 7, plus any files `git rm`'d in step 6. `git add -- <paths>`, then `git commit`. Never `git add -A`: it sweeps up untracked run artifacts (scratch scripts, `.gate/`, stray output files) that were never part of the sync.

**Write the commit MESSAGE to a file and use `git commit -F <path>` — never a heredoc, and never a long `-m` (v2.2.5).** The gates scan the whole command STRING, so a message body that merely *describes* what this sync changed ("adopts the new merge gate", "gh pr merge is now blocked without a fresh artifact") is matched by `gate-before-merge.sh` on the commit that carries it. A sync commit describes gate changes by its nature, which makes this step the most likely place in the whole skill to hit it — and the block is uninterpretable, because it does not tell you whether the gate works or whether your own message was the violation. Same reasoning as the "probes must live in a script file" rule in step 3, arriving from a third direction. Write the message with the **Write tool** (not a Bash heredoc — the heredoc body is part of the command string too) to `"${TMPDIR:-/tmp}/sync-msg.txt"`, then `git commit -F` that path. The short `-m` this step used to prescribe dodged the gate by luck, not design.

**Edit in one tool call; `git add <files>` + `git commit -F <file OUTSIDE the repo>` in the NEXT call (v3.0.3).** Never batch the edit with the commit. The commit hook is `PreToolUse`: it hashes the working tree BEFORE the call runs, so a mutation made in the same call is gated in its *pre-mutation* state — the artifact then describes the parent's tree, and the merge gate reads it as stale. "Commit exactly what was gated" reads as satisfied at the moment you type the batched call, which is why this has to be stated as a SHAPE and not as an intention. Two consumers hit it in one evening. `.gate/last-precommit.json` now carries a `tree` field for exactly this: an artifact tree equal to `HEAD^{tree}` means the mutation was batched with the commit; equal to neither that nor the working tree means an untracked file was swept in by `add -A`.

**The same trap sits one command later, in `gh pr create --body` (v2.2.5).** A PR body describing merge-gating changes is just as much part of the command string as a commit message, and a sync PR describes them by its nature. Use `gh pr create --body-file "${TMPDIR:-/tmp}/sync-pr-body.md"` (written with the Write tool), or `--fill` to reuse the commit message. One reviewer dodged this only by using the GitHub MCP tool instead of `gh` — luck again. **State it as the general rule, because the next instance will be a third command:**

> **Any text DESCRIBING gate changes goes in a FILE, never in a command string.** Commit messages, PR bodies, issue bodies, release notes — anything you pass with `-m`, `--body`, or a heredoc. The gates scan the whole string by design; a block on your own prose is uninterpretable, because it does not tell you whether the gate works or whether your message was the violation it caught.

**The full sequence under v2.1.3+ hooks — the order is load-bearing:**

```sh
git add -- <applied_files from step 7> <git-rm'd paths from step 6> .claude/template-manifest.json
# write the message to a FILE first (Write tool), then:
git commit -F "$TMPDIR/sync-msg.txt"               # PreToolUse: with **Test** present this
                                                   # runs the tests only and writes NO artifact
# --> now delegate ONE `bash hooks/run-gate.sh` run to `ops` (the PO cannot run the gate)
git push -u origin <branch>
gh pr create --fill
gh pr merge --squash --delete-branch               # (or the MCP merge tool)
git checkout main                                  # local main still carries the PRE-sync hooks
                                                   # until it fast-forwards
git pull --ff-only                                 # allowed by BOTH hook versions; if a refusal
                                                   # surprises you HERE, sha256 the hook before
                                                   # concluding anything about the release
git fetch -p                                       # drops the phantom remote-tracking ref
```

**Write the last two as two commands, not as `git checkout main && git pull --ff-only`.** Stated truthfully, because the reason changed under this procedure's feet: the chained form **blocked on v3.0.2** and is **allowed from v3.0.3**, because a bare `--ff-only` pull fetches first and can only fast-forward to the upstream, so its verdict does not depend on which branch the mover lands on — and refusing it would be a denied legitimate command. The mover rule is unchanged for the case it exists for: `git checkout <protected> && git merge <x>` is still refused, because there the landing is real and the branch decides. Keep the two-call form anyway — it is the shape that reads the same under both hook versions, and a consumer on a v3.0.2 checkout still hits the block. The two lines are IN the block on purpose: the reader who needs them is the one who was surprised by a refusal on `main` and is primed to read it as a broken release, and that reader copies from the block, not from the prose under it.

**A fast commit with no visible output is the harness dropping non-blocking hook stderr, not the hook skipping.** `pre-commit-test.sh` does not path-filter and has no "no source files" branch — it runs the Test Command (or `run-gate.sh`) on every commit, unconditionally. The `passed. (Ns)` marker is printed and you do not see it. **The elapsed seconds are the evidence**; a fast commit means a fast Test suite.

**Read the gate's verdict from `GATE PASS` or `.gate/last-pass.json` — NEVER from the exit code of a pipeline (v2.2.6).** `bash hooks/run-gate.sh | tail -100` is an entirely natural thing to do with a multi-minute chatty command, and it reports **`tail`'s** exit code, not the gate's. A consumer's delegated `ops` agent hit this and reported honestly that it could not supply the rc; a less careful one gets `0` from `tail` on a red gate. Two rules, both cheap:

- **Do not pipe the gate if you need its rc.** If you must pipe for volume, set `set -o pipefail` first — the same hazard the placeholder sweep already warns about, one command over.
- **The authoritative sources are the `GATE PASS <sha>` line and the artifact** (`.gate/last-pass.json` — `"status":"pass"` with sha/tree matching HEAD). The gate is LUCKIER than the sweep precisely because it writes an artifact; use it. Quote the `GATE PASS` line in the report rather than asserting "exit 0".

Gate **after** the commit, never before: the artifact must match the PR head by sha or tree. A gate run before the commit reports "artifact stale" at merge time unless the tree is byte-identical either side of the commit.

**The commit gate keys on the WORKING TREE at gate time — commit exactly what was gated.** A chained `git add … && git commit` is fine (the tree the gate hashed is the tree the commit gets); so is `git commit -a`. A *partial* add after the gate ran mismatches by design — the committed tree is not what was gated — and the merge gate will correctly demand a fresh run.

CI fires on `pull_request` and on push-to-main; a bare branch push produces **no** run. Open the PR first, then look up the run id — an empty workflow list right after `git push` is not a CI failure.

## Pre-sync verification

**When a release changes refusal behaviour on commands people type by hand, nobody syncs until this comes back.** The risk is not a missed bypass — it is a regression that blocks routine work and gets the guard switched off. Verify **read-only against the TAG**: extract the hooks from the tag into a throwaway repo; do not install, do not sync, do not touch your tree.

### The three rules every row must follow

1. **Every want-0 row is paired with a want-2 row in the SAME fixture repo.** A `PROJECT_CONTEXT.md` with no `**Gate**:` field makes the hook exit 0 *before it decides anything*, so every want-0 in that repo passes vacuously. An unpaired want-0 is **VOID, not passing** — say "void" in the report; a void row counted as green is worse than a missing row, because it is claimed coverage.
2. **Assert the fixture carries the property before measuring it.** A probe that cannot fail looks exactly like one that passed.
3. **`set -o pipefail`, and check the payload parses (`jq .`) before you believe a verdict.** An unescaped `"` makes the hook fail closed at **exit 2, which reads as "gated" and is not.** In one night three sessions hit the pipe-exit-code error and two hit the quote one.

Write probe scripts with your file-writing tool and run `bash <path>`. A heredoc containing git clauses is refused by the gates' own whole-string scan — the heredoc body IS the command string.

### The three named traps, each hit by a different session

- A fixture `PROJECT_CONTEXT.md` with **no Gate field** — the hook exits 0 before deciding, and every row reads as allowed.
- **No remote after `git init`** — `pull --ff-only` is then correctly BLOCKED for a reason that has nothing to do with the rule under test, and it reads as a regression.
- **Testing a gated-clause rule on a branch where nothing is gated** — on a feature branch the answer is 0 whatever the rule does.

### Commit the predicted table BEFORE running anything

Write down every row with its predicted verdict **and the reason**, and commit that file first. Then run. A matching result cannot be post-hoc rationalised, a mismatch is unmissable, and the git order is the proof. This costs one commit and is the only thing that distinguishes a prediction from a description.

### Delete-the-guard bookkeeping

For each new arm: delete the arm, re-run the suite, count the rows that flip. **An arm whose deletion flips zero rows is untested**, however green the suite looks. **Rows that flip because they share an INSTRUMENT are one piece of evidence, not many** — two probe rows that flip under both arm 1 and arm 2 are arm-agnostic and do not count toward the zero-flip rule. Report the deduplicated numbers (3 / 6 / 12, not 5 / 8 / 12) and say which rows were deduplicated.

### The order

**Verification → restart → sync → live re-run.** Verification runs against the tag before anything is installed. **Restart** the session after user-level files are copied — a running session keeps the previous skill and agent definitions, including this one. Only then sync, and re-run the probes **live**, on the installed hooks: the tag run proves what the release contains, the live run proves what the machine now enforces, and only the second one is delivery.

## Rules

- NEVER auto-update a `CONFLICT` file without user confirmation
- NEVER delete a project-owned file the template never shipped. A `TEMPLATE_DELETED` file is different: ask, and delete it with `git rm` when the user accepts (step 6)
- NEVER apply an `auto_merged` body without checking it for dropped lines — and, for a hook, without a `bash -n`
- NEVER finalize without the hook-script verification (step 6b), sourced libs included — a missing script or lib fails open and silently disables enforcement
- NEVER register PRESENT hooks with `source="template"` in step 6b — `source="skip"` for present-but-untracked (registration must not overwrite local edits); `source="template"` is ONLY for scripts missing from disk (step 3)
- NEVER write a path from the template that already EXISTS in the project without an explicit conflict resolution (invariant I1) — a `new_template_files` entry that is present on disk is presented as a CONFLICT defaulting to keep-mine (`source="skip"`), never added with `source="template"` on the strength of a "yes" to "add this new file?"
- NEVER write `.claude/settings.json` before every script it references exists on disk (invariant I2), whichever step introduced those scripts
- NEVER record `rc=127` or `rc=126` from `bash -n` (or any checker) as a PASS — 0 and 2 are the only verdicts, 126/127 are hard ERRORS naming the path, and "the check did not run" is a raised `FileNotFoundError`, not a return code (step 4)
- NEVER exec a checker by bare name, and never by a hardcoded platform path — resolve it once with `shutil.which` (or the shell equivalent) and exec the absolute path it returns (step 4)
- NEVER hand-assemble or re-type `applied_files` entries — collect the tool results verbatim
- ALWAYS re-run `template_compute_status` after finalize and report anything other than a clean result
- ALWAYS call `template_finalize_sync` at the end, even if no files changed (updates `lastSynced`)
- NEVER fail or roll back a sync because a version label would not resolve (step 7b), and NEVER write `templateSyncToolsVersion` from anything but a server-reported value
- All hashing, diffing, and placeholder replacement is handled by the MCP tools — do NOT compute hashes or apply placeholders manually
