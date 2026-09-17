> Moved from mcp-dev-servers at v0.3.8 in toolkit v4.0.0; the server it describes ships from `server/` in this repo from v4.0.0. Where this doc and the artifact disagree, measure the artifact and report the disagreement — the rule this doc was written under.

# `template_migrate_manifest` — the v2 → v3 migration contract

**Status: current as of 0.3.7.** This file is the contract surface for the v2 → v3 manifest
migration. Until now that contract lived in an implementation plan and a tool docstring,
which is why a caller could read an entire sync skill end to end and never learn the
migration tool existed — the gap this document closes.

**When this file and a docstring disagree, measure the artifact and report the
disagreement.** That is not a disclaimer; it is what two consumer sessions did in September
2026, correctly, and it found a docstring that had promised the opposite of what the code
did since the v3.1 reversal. A test now pins the docstring to the behaviour
(`tests/test_template_sync_docstring_contract.py`), but the rule stands: the written file is
the authority, prose is a claim about it.

Fields carry the release that introduced them. **`requires_skill` is enforced as of 0.3.7**
— it was declared-but-ignored before that, and §8 says exactly what it now does.

**v4.0.1 note.** The v2-era `lastSynced`/`lastSyncedVersion`/`lastSyncedVersionOf` keys
(`v3.SUPERSEDED_KEYS`) are now dropped unconditionally by both this tool and
`template_finalize_sync`, reported in `superseded_keys_dropped` — they duplicated the
server-authoritative `template_version`/`template_commit` under v3 and could only drift. A
new read-only tool, `template_verify(project_path, mode="pre_commit"|"post_commit")`, checks a
consumer's end state (manifest shape, superseded keys absent, missing/unknown keys, gate
artifacts, region markers, and more) without writing anything — see `docs/template-sync.md`.
**`manifest_version` stays 3**: every v4.0.1 manifest field is additive, so an older server
still round-trips a v4.0.1 manifest correctly, preserving fields it does not recognise.

---

## 1. Who calls it, and when

**The caller calls it explicitly. Nothing else performs a v2 → v3 migration.**

`template_load_manifest` does **not** auto-migrate v2 → v3. It reports
`migration_required` and returns (`template_sync_mcp.py`, the v2 branch). The asymmetry with
v1 is real and easy to trip over:

| From | Who migrates | Persisted by |
|---|---|---|
| v1 → v2 | `template_load_manifest`, **in memory** | the next `template_finalize_sync` |
| v2 → v3 | **`template_migrate_manifest` only** | that call, when not `dry_run` |

**`migration_required` does not mean "this project needs migrating".** It is literally
`load_ownership(manifest["templateRepo"]) is not None` — it reports that the *template
checkout* ships `templates/ownership.json`. It says nothing about whether the migration will
succeed: a `gate_self_reference` hit refuses, and a missing `backup_dir` is a hard error.
Read as an imperative it produces a forced step that can dead-end.

**`template_finalize_sync` neither migrates nor refuses a v2 manifest.** It dispatches on
`is_v3(manifest)`; handed a v2 manifest it takes the v2 path and writes a v2 manifest back
out. So **skipping the migration is silent and permanent** — no error, nothing lost,
`migration_required: true` on every future sync. The migration is not something a flow falls
into; it is something the caller does on purpose.

---

## 2. The four response shapes

A response is one of four shapes. **Test them in this order** — the version question is
answerable only after the first two are excluded.

```
1. {"error": ...}                                    -> refused. Say NOTHING about versions.
2. {"migrated": false, "dry_run", "reason"}           -> already v3. Nothing migrated. No fields.
3. full field set, "dropped_resolutions" ABSENT       -> server predates 0.3.4.
4. full field set, "dropped_resolutions" PRESENT      -> read it; truthiness for content.
```

Shapes 1 and 2 are **sparse**: they carry no field from the table in §3. A caller that tests
field presence before excluding them concludes "old server" from a manifest that was simply
already v3, or from a refusal.

**Four tests, in this order. Key presence does not answer the version question:**

```
1. "error" in result                              -> refused. Report it; say nothing
                                                     about versions.
2. result.get("migrated") is False and "reason"   -> already v3. Nothing migrated.
   in result
3. server_version from the template_load_manifest -> the VERSION question.
   response
4. isinstance(result.get("dropped_resolutions"),  -> the CONTENT question.
   list) and result["dropped_resolutions"]
```

**An earlier draft of this file said `"dropped_resolutions" in result` answers the version
question. It does not, and that sentence was a defect.** Absence has three causes — the
server predates 0.3.4, no migration ran, or the call errored — so `in` conflates them, and a
caller that reaches for it reports "old server" about a project that was simply already v3.
A key present with a non-list value passes `in` while failing truthiness, which lands a
caller in "nothing was dropped" from a value that says nothing of the kind. This server
always emits a list in a successful response, but nothing in the response lets a caller
verify that, and `server_version` is a direct answer where key presence is an inference.

Reported by the `claude-code-toolkit` controller reading this file against their sync
skill's migration step, which ships these four tests. Their step is the reference
implementation of this section.

## 3. Fields (success and `dry_run` responses)

**Every field below is unconditional in a successful response, except the two marked
presence-keyed.** The sparseness is otherwise per response shape, never per field. This is the opposite of the
`region_*` convention elsewhere in this server, where a field appears only in the hazardous
case; a reader who carries that habit here concludes that an empty list cannot happen and
reads absence as "none".

| Field | Type | Notes |
|---|---|---|
| `manifest` | object | the new v3 manifest |
| `dropped_entries` | `[path]` | project-class entries removed |
| `dropped_resolutions` | `[{path, resolution, ownership}]` | see §4 |
| `dropped_file_keys` | `[{path, keys}]` | see §4 (0.3.5) |
| `redundant_project_file` | `[path]` | byte-identical copies. **Suggestion only, never deleted** |
| `project_md` | string or `null` | `null` when the project already had one |
| `project_md_existing` | bool | |
| `project_md_bytes` | int | |
| `hunk_count` | int | `@@` lines in the out-of-region diff |
| `migration_base` | string | **never `null`** — see the trap below |
| `region_was_seed` | `true` / `false` / `null` | tri-state; `null` = not comparable |
| `region_left_in_place` | bool | the region stays in `CLAUDE.md` |
| `region_bytes` | int | UTF-8 bytes of the region **body**, markers excluded |
| `gate_self_reference` | `[{key, path}]` | **non-empty refuses in write mode** |
| `gate_unverified` | bool | a `**Gate**:` is declared and this tool did not run it |
| `unknown_keys` | `[key]` | unknown top-level keys, preserved |
| `unknown_file_keys` | `[{path, keys}]` | annotations on entries that **survive** |
| `skill_version` | string | echoed as **claimed**, never verified (0.3.7) |
| `skill_version_unknown` | `true` | **presence-keyed** — only when the caller passed none |
| `skill_version_bypassed` | `true` | **presence-keyed** — only when the sentinel was used |
| `warnings` | `[string]` | |
| `dry_run`, `migrated` | bool | |
| `backup` | `{claude_md, manifest}` or `null` | |
| `written` | `[path]` | |

### Two sentinel traps

**`migration_base` is never `null`.** When the held revision cannot be resolved it is the
string `"unavailable"`, accompanied by a `migration_base_unavailable` warning. A caller
testing `if not migration_base` gets a truthy sentinel and proceeds as though the base
resolved. **Test the warning, not falsiness.** The value is consumed in the `project.md`
header, which is why it is a label rather than `null`.

**`region_was_seed` is tri-state.** `null` means the comparison could not be made — no
region, or no resolvable base — not "false".

---

## 4. What a dropped record means (and what it does not)

`dropped_resolutions` reports entries whose v2 `"resolution": "keep-mine"` record is
discarded, because **v3 has no keep-mine class**. Since 0.3.5 each row carries the class the
file lands in, and **that class, not the dropped record, is what decides whether anything is
at risk**:

| `ownership` | What the next apply does | Action needed |
|---|---|---|
| `"template"` | overwrites the deviation | **re-apply or upstream it** |
| `"once"` | **keeps** the project's file, writes 0 bytes | none |
| `"project"` | never written by the server | none |
| `null` | no rule matches; untracked | none |

A caller that warns on every row cries wolf. Measured on a live consumer, all four of their
deviation-bearing entries were safe — two `once`, two untracked — so a step keyed on the bare
list would have produced four warnings and no true ones. Four false alarms teach a consumer
to skim the step, and then the real case is skimmed too.

`dropped_file_keys` (0.3.5) reports consumer annotations on entries the migration **drops** —
a key like `reason` on a project-class entry, which no other field reported. It and
`unknown_file_keys` partition: a surviving entry appears in the latter and never in the
former. Superseded v2 keys are excluded, and `resolution` stays in its own list. **The values
survive** in the pre-migration manifest copied to `backup_dir`.

---

## 5. What it writes, what it refuses, and what it never touches

Writes (non-`dry_run` only):

- `.claude/template-manifest.json` — the v3 manifest.
- `.claude/rules/project.md` — **only if absent**. An existing one is never overwritten
  (`project_md: null`, `project_md_existing: true`).
- `backup_dir/CLAUDE.md.pre-migration` and `backup_dir/template-manifest.json.pre-migration`.

**`CLAUDE.md` itself is never written by this tool** — only copied to the backup. The apply
step later in the same sync is what rewrites it.

`project.md` gets a header plus the out-of-region hunks fenced as ` ```diff `. **The
PROJECT-CUSTOM region is not copied into it.** Under the v3.1 reversal the region stays in
`CLAUDE.md`, so copying it would duplicate rather than relocate it — and the duplicate is the
dangerous half: not because an unscoped `project.md` fails to deliver (corrected in v4.0.1,
item 14 — it loads at every session start, same as the region, once it carries no `paths:`
key), but because a rule written in BOTH places exists twice and drifts the moment either copy
is edited. Keeping one authoritative copy (the region) and a reported diff (here) avoids that;
writing the same content into both is the actual hazard. The region is
reported instead (`region_left_in_place`, `region_bytes`, `region_was_seed`).

Refusals:

| Condition | Behaviour |
|---|---|
| manifest is v1 (or has no `version` key) | **error** (0.3.5). Run load + finalize to persist v2 first |
| `gate_self_reference` non-empty | error in write mode; returned as data in `dry_run` |
| `backup_dir` empty and not `dry_run` | error — use `dry_run` to preview |
| manifest already v3 | no-op shape 2; writes nothing |
| `requires_skill` declared and `skill_version` absent, below floor, or malformed | **error in write mode only** (0.3.7) — see §8 |

Idempotent: calling it on a v3 manifest is harmless and writes nothing.

---

## 6. The order

```
1. template_load_manifest              -> migration_required, server_version, capabilities
2. your own gate                        -> stop below the server version you need
3. template_migrate_manifest(dry_run=True)      -- no backup_dir needed
4. inspect: gate_self_reference (fix and restart if non-empty), dropped_resolutions
   (ownership == "template" rows), dropped_file_keys, region_was_seed,
   project_md_existing, migration_base
5. template_migrate_manifest(backup_dir=...)    -- REQUIRED, else hard error
6. template_compute_status / template_apply_file / template_finalize_sync
```

**Always do step 3.** It is the only way to see a `gate_self_reference` refusal before the
consumer is mid-sync, and it costs nothing.

`template_load_manifest` must be the first `template_*` call: the manifest's
`requires_server` floor is enforced **there and nowhere else**. `template_compute_status` and
`template_apply_file` do not re-check it, so skipping the load against a manifest that
declares a newer server yields a normal-looking status instead of a refusal.

---

## 7. Which server is actually running

`server_version` in the `template_load_manifest` response is the only per-session
observable. It is read from the imported source, so it is correct for an editable install;
`server_source` says which checkout that is.

- **Never** trust `pip show` or the `dist-info` — an editable install's metadata is stamped
  once at install time. Measured: `pip show` reporting 0.3.0 while the load response said
  0.3.2.
- A running process keeps the build it imported at spawn. **Restart to pick up a release;
  do not reinstall while servers are running** — locked launcher executables have left this
  venv with no shim mid-flight.

---

## 8. The two floors

| Floor | Lives in | Enforced | Direction |
|---|---|---|---|
| `requires_server` | the project's manifest | `template_load_manifest` **only** | raised monotonically by `finalize`, reported as `requires_server_raised` |
| `requires_skill` | the toolkit's `templates/ownership.json` | `template_migrate_manifest`, **write mode only** (0.3.7+) | declared by the toolkit, read at call time; capability `skill_version_floor` |

`requires_server` cannot protect the *first* migration: a v2 manifest carries no floor, and
no code shipping later reaches a process already running. That gap belongs to the caller's
own gate.

`requires_skill` is the mirror image — an old caller against a new server, which is the
likelier direction: this server advances on any pull from a working tree, while the skill
needs a deliberate re-copy, and a `/mcp` reconnect hands a session a brand-new server while
its loaded skill body stays whatever it was. Since 0.3.7 `template_migrate_manifest` takes
`skill_version` and compares it to the declared floor. **Gate on
`"skill_version_floor" in capabilities`, not on the server version.**

| `skill_version` | Write mode | `dry_run` |
|---|---|---|
| absent | **REFUSED** | proceeds, `skill_version_unknown: true` |
| tag-shaped, ≥ floor | proceeds | proceeds |
| tag-shaped, < floor | **REFUSED** | proceeds, refusal text in `warnings` |
| exactly `not-a-skill` | proceeds, `skill_version_bypassed: true` | same |
| anything else | **REFUSED** (named mismatch) | proceeds, refusal text in `warnings` |

Four things about it are load-bearing, and each is pinned by a test:

- **Absence is the signal, not a low version.** A body too old to carry the instruction sends
  nothing at all, so `skill_version` missing is what identifies a stale skill.
- **The value comes from the CALLER, never from reading the installed
  `~/.claude/skills/sync-template/SKILL.md`.** That file reports the *disk*; the failure being
  gated is a session running a body it read at startup, so a disk read returns a confident
  green in exactly the stale case. It works because the threat is staleness, not deceit.
- **`dry_run` is never refused.** Inspection stays open, because previewing is what surfaces a
  `gate_self_reference` before a consumer is mid-sync.
- **The sentinel fails closed.** `not-a-skill` is exact and case-sensitive; `not_a_skill`,
  `Not-A-Skill` and every other near miss **refuse**. A mistyped sentinel that refuses is a
  nuisance; one that bypasses is the guard quietly not existing.

Both sides are tag-shaped: the floor reads `">=v3.1.3"` and the skill's marker `v3.1.3`. A
bare `3.1.3` is a **named mismatch, not a synonym** — this server does not normalise the two
together, because a second, disagreeing normalisation elsewhere is how the toolkit's emitter
once broke as a git ref. A floor this server cannot parse is left as found and reported as
`requires_skill_unparseable`: refusing on a value the parser failed to read would turn a bug
here into a consumer's outage, and guessing a floor is worse than having none.

The echoed `skill_version` is reported **as claimed, never as verified** — no field here
implies this server checked something it cannot check.
