# B3 positive control — heading-anchored placement check

Real three-way merge from the example-project v3.0.3 sync (`60e4b0d` -> `86561fe`),
file `PROJECT_CONTEXT.md`. Not synthetic: this is the merge the server actually
produced, and the misplacement is why the file was spliced by hand instead.

## Files

| file | what it is |
|---|---|
| `base.md`     | common ancestor — the template at `60e4b0d`, placeholders unfilled |
| `template.md` | the template at `86561fe` (v3.0.3) |
| `project.md`  | the project file before the sync |
| `merged.md`   | what `template_get_diff(diff_type="three_way")` returned as `auto_merged` |

## What the template ADDED

Exactly one block, one line, an HTML comment beginning:

    <!-- Declaring BOTH means the Test runs on commit and the Gate does not, ...

In `template.md` it sits **immediately after** `- **Gate**: {{GATE_COMMAND}}`,
under the `## Commands` heading. It annotates the Gate field.

## Where the merge put it

In `merged.md` it lands **at the end of the `## Signal Plans` section**, directly
after the line

    The conflict matrix and per-pair intergreen config are in `src/core/signal/config.ts`.

which is ~30 lines from the `**Gate**:` line it annotates, and under a heading the
template does not even have (`## Signal Plans` is project-added).

## Expected verdict

**RED.** The check must flag this.

- heading in template : `## Commands`
- heading in merged   : `## Signal Plans`
- mismatch            -> placement violation

## Why the obvious check does NOT catch it

Line-distance anchoring on the nearest preceding template line fails here: the
anchor is `- **Gate**: {{GATE_COMMAND}}` in the template and
`- **Gate**: npm run gate` in the project, so exact-anchor lookup finds nothing
and the check degrades to "could not determine" precisely where it is needed.
Heading anchoring is unaffected — `## Commands` is byte-identical in all three.

## What the existing checks say about this merge

    has_conflicts : false
    conflict_count: 0
    dropped_lines : []

Every step-4 check passes. Nothing is lost. The merge is still wrong, which is
the whole point of the item: **a clean merge is not a correct merge, and
placement is a second failure mode with the same clean signature.**

## Negative control (must stay GREEN)

Take `merged.md` and move the added comment line to immediately after
`- **Gate**: npm run gate`. That is the hand-splice that actually shipped
(see `b2ef758:PROJECT_CONTEXT.md`). Same content, correct section -> the check
must pass. Without this arm the check cannot be distinguished from one that
fires on every added block.

## Provenance

Fixture contributed by a downstream consumer, 2026-09-05; real three-way
content, sanitized; red arm = merged.md (added block lands under
`## Signal Plans`, delta 9), green arm = spliced-negative-control.md (under
`## Commands`, delta 1).
