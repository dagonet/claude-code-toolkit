# claude-code-toolkit — downstream `/sync-template` findings

**Date:** 2026-07-19
**Variant:** `dotnet`
**Sync:** `9021ddc` → `ebab66e` (the delegation-first model bump)
**Reporter:** a downstream project (`MotorsportManagerAgent`) syncing the template

This sync pulled 24 auto-updates cleanly but produced **3 conflicts**
(`CLAUDE.md`, `AGENT_TEAM.md`, `PROJECT_CONTEXT.md`) and exposed several
toolkit-side issues worth fixing upstream. Written up here as feedback; nothing
below was changed in the toolkit.

---

## What a naive "accept template" would have lost

| File | Loss |
|---|---|
| `CLAUDE.md` | The project's checked-in **"Context-Mode Routing Rules"** section (~130 lines, appended below the template body). It is intentionally in the repo so a fresh clone inherits the ctx-routing rules. A blind accept-template drops it silently. *(Resolved here via a real 3-way merge: template body + preserved project tail.)* |
| `AGENT_TEAM.md` | A project escalation refinement line ("count the stall as one strike…"). Minor — intentionally superseded by the new model here. |
| `PROJECT_CONTEXT.md` | **Nothing** — clean 3-way merge; the project's `.NET 10` / per-project build commands + mixed-target caveat were preserved (`locallyModified` kept true). |

The `CLAUDE.md` case is the important one: it is a **recurring** loss. Any
project that appends to `CLAUDE.md` will hit this conflict on *every* template
`CLAUDE.md` change, and a careless sync clobbers the addition.

---

## Findings (prioritized)

### 1. [BUG] `enforce-delegation.sh` is missing from the `dotnet` variant

The `ebab66e` model registers `hooks/enforce-delegation.sh` as a `PreToolUse`
hook and documents it as the mechanical enforcer of "the PO never edits code."
But:

- `templates/dotnet/.claude/settings.json` **references** `hooks/enforce-delegation.sh`
  (matchers `Edit|Write|NotebookEdit` and `Bash`).
- `templates/dotnet/CLAUDE.md` and `templates/dotnet/AGENT_TEAM.md` **document** it.
- `templates/dotnet/hooks/enforce-delegation.sh` **does not exist**.
- The script **does** exist at the toolkit **root** `hooks/enforce-delegation.sh`
  — i.e. it was never materialized into the variant's `hooks/`.

Consequence: a fresh sync/clone of the `dotnet` variant registers a hook whose
script is absent. The registration uses a WARN-wrapper that **fails open**
(`exit 0` on 127) — so the delegation hard-block the new model advertises is
**silently OFF**. The docs promise enforcement that never runs. `/sync-template`
step 6b is designed to restore missing hook scripts, but it can only pull from
the variant, where the file isn't present — so it can't self-heal. (I copied it
from the toolkit root by hand.)

**Fix:**
- Ensure the variant-materialization step copies **every** root hook the variant
  references into `templates/<variant>/hooks/`.
- Verify the other variants — this is likely not `dotnet`-only.

**Add a CI invariant** (highest-value item here): for each variant, every
`hooks/*.sh` referenced by that variant's `settings.json` **and** by any
`.claude/agents/*.md` `hooks:` frontmatter MUST exist and be non-empty in that
variant's `hooks/`. This class of "settings references a hook the variant
doesn't ship" fails open and is invisible without exactly this check.

### 2. [DESIGN] No project-custom region in `CLAUDE.md`

Projects legitimately extend `CLAUDE.md` (here: the ctx-routing rules, kept
checked-in for fresh clones). The template offers no clean extension point, so
each template `CLAUDE.md` change is a 3-way conflict that a naive sync can
clobber.

**Fix:** add a sentinel region the sync never touches, e.g.

```markdown
<!-- PROJECT-CUSTOM:BEGIN — sync-template never edits below this line -->
<!-- PROJECT-CUSTOM:END -->
```

and have `template-sync-tools` treat content inside it as project-owned (merge
template changes above/outside, preserve the region verbatim). Turns a recurring
conflict into a clean auto-update. (Alternatively: document that project-scoped
rules belong only in a specific template-owned-but-never-overwritten file — but
an in-`CLAUDE.md` region is what projects actually reach for.)

### 3. [PROCESS] Model-changing bumps ship without migration notes

`ebab66e` flips the entire operating model — PO-never-codes at any tier, T1 now
spawns a coder, new `ops` agent, `enforce-delegation` hard-block, code-reviewer
from T2+ (was T3+), tester messaging — and it arrives downstream as a bare
`CLAUDE.md` / `AGENT_TEAM.md` conflict with no CHANGELOG or migration note. A
downstream operator has to reverse-engineer the intent from the diff.

**Fix:**
- Ship a short migration note / CHANGELOG entry for behavior-changing revisions,
  especially operating-model shifts, listing what changed and what a project must
  add (`ops` agent, `enforce-delegation.sh`).
- Have `/sync-template` detect that `CLAUDE.md`/`AGENT_TEAM.md` changed and
  surface "this bump changes the workflow model — review the diff before
  accepting," rather than presenting it as an ordinary conflict.

### 4. [MINOR] Manifest `locallyModified` flag goes stale

`.claude/agents/dotnet-coder.md` was stored in the manifest as
`locallyModified: true` ("Project-specific agent"), but on disk it equalled the
last-synced template — `template_compute_status` (which recomputes from disk)
correctly classified it `AUTO_UPDATE`. Trusting the stored flag would have
skipped a valid update. The stored boolean is redundant with a recompute and can
drift.

**Fix:** drop the stored `locallyModified` flag, or always recompute it from the
current file vs. the at-sync hash and treat that as authoritative.

### 5. [MINOR] CRLF churn on sync

`git add` of the synced set warned `CRLF will be replaced by LF` on **every**
file. `.gitattributes` normalizes it, so it's cosmetic, but it means part of
each file's "modification" is line endings, not content — noise in review.

**Fix:** ship template files with LF endings consistent with the shipped
`.gitattributes` so a sync doesn't produce line-ending-only churn.

### 6. [BUG] `template-sync-tools` `finalize` stores hashes unvalidated

`template_finalize_sync` writes whatever hashes it's given straight into the
manifest with no validation. Hand-assembling the 29-entry `applied_files`
payload, I slipped stray spaces into 3 of the SHA256 values; `finalize` accepted
them, silently corrupting the manifest. It only surfaced on a follow-up
`template_compute_status` (which then showed false `AUTO_UPDATE`/`PROJECT_CUSTOM`
drift on those 3 files).

**Fix:**
- `finalize` should reject any hash not matching `^[0-9a-f]{64}$` (and any
  entry whose `file_path` isn't in the plan).
- The `/sync-template` skill should build the `applied_files` payload
  programmatically from the `apply_file` results, never by hand — and should
  always re-run `compute_status` after `finalize` as a self-check (clean sync ⇒
  `auto_update: 0, conflict: 0`).

---

## Suggested CI invariant (summary of the highest-value fix)

For every variant under `templates/`:

1. Collect all `hooks/<name>.sh` references from `.claude/settings.json` and from
   every `.claude/agents/*.md` `hooks:` frontmatter.
2. Assert each referenced script exists and is non-empty in that variant's
   `hooks/`.
3. Fail CI otherwise.

This alone would have caught finding #1 at build time.

---

## How this sync was resolved (for reference)

- `CLAUDE.md`: 3-way merge — adopted the new delegation-first body, preserved the
  project's Context-Mode Routing Rules tail. Recorded `locallyModified: true`.
- `AGENT_TEAM.md`: accepted template (the project-unique lines were all old-model
  wording being intentionally replaced).
- `PROJECT_CONTEXT.md`: clean 3-way merge; `.NET 10` / per-project commands kept.
- `enforce-delegation.sh`: copied from the toolkit **root** into the project's
  `hooks/` and registered in the manifest, since the variant doesn't ship it.
- New `ops` agent adopted. Manifest advanced to `ebab66e`; `compute_status`
  verified clean (0 auto-update / 0 conflict / 0 drift) after fixing the 3
  hand-typed hash typos from finding #6.
