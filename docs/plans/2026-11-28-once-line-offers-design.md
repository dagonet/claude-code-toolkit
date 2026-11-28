# Once-class line offers: design (B-18, v7.1.0)

Approved by the user on 2026-11-28 (dashboard question 87, "Approve as proposed").

## Intent and why

A project's `PROJECT_CONTEXT.md` is once-class: a sync never overwrites it. When the template
changes a line there, a project that still holds the old line keeps it for good. Measured case:
v4.0.1 changed the `**Ollama**` line (it pointed at `CLAUDE.local.md`, which is no longer
shipped), and all six consumers still held the old line in November 2026.

The backlog item asked to present each pending once-note hunk as an adopt/skip choice. Reading
the code showed that this would not have caught the case: `notes_hunks` drops every `**Key**:`
line from its hunks (key lines are "the audit's business"), and `audit_keys` records a changed
template default only for required keys. `Ollama` is an optional key, so the change was reported
nowhere. The design therefore keys on the project's own file, not on the note mechanism.

## Goals

- When the template changed a line and the project still holds that line exactly in its old form,
  the sync shows old and new and the user answers adopt or skip, per line.
- Adopt replaces exactly that line. Nothing else in the file changes.
- A skipped line is offered again at the next sync, for as long as the project holds the old form.

## Non-goals

- Lines the project customized: never offered, never touched (as today).
- Once-class files other than those with `"audit": "keys"` in `templates/ownership.json`
  (today: `PROJECT_CONTEXT.md` only).
- Template changes older than the project's current base. The feature works from the first sync
  run with a v7.1.0 server; it cannot find leftovers from earlier releases.
- Pure additions and pure deletions in the template. New keys are already reported
  (`optional_absent`), new comments by `template_notes_changed`.
- No new `template_verify` line and no change to the `once_notes_changed` line (the line count
  and the skill's 8a table stay as they are).
- No new MCP tool.

## Anti-goals

- An edit to a once-class file that the user did not answer for.
- A placeholder token (`{{...}}`) written into a project file.
- An offer built from a guessed pairing of old and new lines.

## Approaches considered

1. **Offer the existing note hunks** (the backlog wording). Rejected: the hunks hold no key
   lines, so the measured case stays invisible; and a hunk is a patch against the template, which
   need not apply to the project's file.
2. **Line pairs matched against the project's file** (picked). The server pairs old and new lines
   from the template's own diff, strictly, and offers a pair only when the old line stands exactly
   once in the project's file. The skill asks and makes the one-line replacement. Simple, exact,
   and wrong pairings cannot occur by construction of the two pairing rules below.
3. **A server tool that performs the replacement.** Rejected for now (KISS):
   `PROJECT_CONTEXT.md` is on the main thread's write surface (`hooks/enforce-delegation.sh`), the
   server hands over both lines verbatim, and an exact one-line Edit needs no new tool.

## Design

### Server: `line_offers` in the status

For a once-class file whose rule has `"audit": "keys"`, with a project copy and a resolvable
base, `compute_status_v3` adds to `info["key_audit"]`:

- `line_offers`: a list of `{"old": <line>, "new": <line>}`, lines without their line ending;
- `line_offers_base`: the commit the offers were measured from.

**Base.** If the manifest's `pending_once_lines` holds an entry for the file and its
`from_commit` resolves, that commit is the base. Otherwise the base is the one `resolve_base`
gives today (the manifest's `template_commit`), and `line_offers_base` is the manifest's commit.
Both sides of the diff are `template_content()` renderings, as for `notes_hunks`.

**Pairing.** Unified diff of base against the current template with no context lines. In a hunk
that has removed and added lines:

1. a removed `**Key**:` line and an added `**Key**:` line with the same key name are a pair;
2. a hunk of exactly one removed and one added line is a pair, whatever the lines are.

Nothing else is paired. A hunk with only removed or only added lines yields nothing.

**Offer.** A pair is an offer when all hold: old differs from new; new holds no `{{...}}`
token; old stands in the project's file as a whole line exactly once (a trailing `\r` on the
project's line is ignored for the comparison).

`line_offers` is added to the server's capability list.

### Server: `pending_once_lines` in the manifest

`finalize_v3` already computes the status against the old manifest before it writes the new one.
From that status it writes `pending_once_lines`: one `{"file", "from_commit"}` per file whose
`line_offers` is non-empty, with `from_commit` = that file's `line_offers_base`. By then the
skill has applied the adopted lines, so what remains are the skipped ones. An empty result
removes the key. A status error leaves the stored list untouched and adds a warning, as for
`pending_once_notes`. The finalize response returns `pending_once_lines`. The key joins
`KNOWN_TOP_LEVEL_V3`.

Consequences, all from the one base rule: a skipped line is offered again at the next sync; a
line the template changed twice is offered with the newest text; an adopted or hand-edited line
drops out; an entry whose commit no longer resolves is replaced by the normal base.

### Skill: one question, exact edits

In `skills/sync-template/SKILL.md`, after the status is computed and before finalize, when the
server lists the `line_offers` capability and a file has offers:

- show every pair, numbered, old above new, per file;
- ask once which to adopt (all, none, or numbers); no answer means skip;
- for each adopted pair, replace exactly the old line with the new line in that file (Edit tool,
  whole-line match); if the old line is no longer there exactly once, skip it and say so;
- the edited file goes into the sync commit;
- the report gains `Adopted lines:` and `Skipped lines (offered again at the next sync):`, the
  second taken from the finalize response's `pending_once_lines`.

This is the only edit a sync makes to a once-class file, and only on the user's answer; the
skill's "never edits a once-class file" sentences get that exception. Without the capability the
step is skipped, so the skill's server floor does not move.

## Left to the builder

- Function names and where the helper lives in `server/src/template_sync/v3.py`.
- The exact wording and step number in `SKILL.md`, and which `git add` line of step 9 takes the
  edited file.
- Test names. The cases are in the plan.
