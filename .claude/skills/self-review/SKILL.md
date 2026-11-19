---
name: self-review
description: Build the toolkit's periodic self-review report from local session counts and the Claude Code changelog. Triggers on /self-review.
disable-model-invocation: true
---

# /self-review

Writes `docs/self-review/<YYYY-MM-DD>.md` from counts taken from Claude Code session records on one or more machines, plus the Claude Code changelog. Run it in a toolkit checkout. It never ships to consumers and applies nothing by itself.

## Steps

1. Count this machine. Run `python3 scripts/self-review-count.py --since <date of the previous docs/self-review report, else 30 days back> --out ~/.cache/cct-self-review/inbox/<label>.json` (on Windows, `python` if `python3` is absent). `<label>` is any short name for this machine. The counter also writes `<label>.local.json` next to it; the merge step ignores that file.
2. Group the corrections. Read the `corrections` in the `.local.json` and group them into behaviour kinds: agent behaviour only, never project content. Add `"correction_kinds": [{"kind": "...", "count": N}]` to the shared JSON (`<label>.json`). Never copy candidate text anywhere else.
3. Ask the user once which other machines to include. For each one, give the two ways in, then continue with whatever is in the inbox, without waiting:
   - **(a) Manual:** run the same counter there, follow its printed "Next:" line, and copy the shared JSON into this machine's `~/.cache/cct-self-review/inbox/`.
   - **(b) Peer session:** if a Claude session on that machine can be messaged, ask it to do (a) and reply with the shared JSON text only. Write that text to the inbox.
   - A machine label that appears in the previous report's table but not in the inbox is named in the header as "not included this time".
4. Merge. Run `python3 scripts/self-review-count.py --merge ~/.cache/cct-self-review/inbox/` and paste its table unchanged. For a repeated machine label the newest run is kept and the merge lists the others as `skipped: ...`; keep those lines.
5. Read the Claude Code changelog (https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md) from the version named in the previous report's header, looking for features that make a toolkit rule redundant or newly possible.
6. Write `docs/self-review/<YYYY-MM-DD>.md` with the template below.
7. Before saving, check the report for project or repo names from the `.local.json` files and remove any that appear.

## Report template

- **Header:** date, window, Claude Code versions and models seen, machine labels, the previous report or "first report", and one line that sessions whose records are on no included machine (for example cloud-hosted ones) are not counted.
- **Key numbers:** the merged table, then the Context Budget figures from the last column of the table in `docs/architecture.md` (*Context Budget*).
- **At most 10 items**, ranked by cost saved or quality gained. Each gives the evidence, the change, the effect, the risk, and the files touched.
- **Since last report:** one line.

## Rule

Nothing is applied; each item waits for the user's approval of that item. The maintainer commits the report in the release PR. Anyone else keeps theirs in their own checkout, and may offer findings upstream via `contribute-upstream`.
