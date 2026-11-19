---
name: self-review
description: Build the toolkit's periodic self-review report from local session counts and the Claude Code changelog. Triggers on /self-review.
disable-model-invocation: true
---

# /self-review

Writes `docs/self-review/<YYYY-MM-DD>.md` from counts taken from Claude Code session records on one or more machines, plus the Claude Code changelog. Run it in a toolkit checkout. It never ships to consumers and applies nothing by itself.

All counter commands below are `python3 scripts/self-review-count.py ...`; on Windows use `python` if `python3` is absent. Every machine uses one exchange directory, `~/.cache/cct-self-review/`: the counter writes there by default, and the files from other machines are copied into the same directory.

## Steps

1. Count this machine. Run the counter with `--since <date of the previous docs/self-review report, else 30 days back>` and the default `--out`. If this checkout is a git worktree, also pass `--clone-root <the directory that holds your clones>`; the counter prints `clone roots: N, notes files: N, Jev event files: N`, and a zero where you expect notes or Jev events means it looked in the wrong place (zeros are normal before notes exist and without Jev). Keep the counter's default machine label (`<os>-<6 random hex>`, made once and kept in the exchange directory as `machine-id`); never ask for one or invent one. If the user insists on choosing a label, it must not identify the machine or its user: never a hostname or a user name. The counter writes `<label>-<date>.json` and `<label>-<date>.local.json` into the exchange directory; the merge step ignores the `.local.json`.
2. Group the corrections. Read the `corrections` in the `.local.json` and group them into behaviour kinds: agent behaviour only, never project content. A kind is a short, generic phrase about what the agent did. It may not name a project, repo, path or person, and may not quote words from the candidates. A candidate that is not a correction gets no kind. Add `"correction_kinds": [{"kind": "...", "count": N}]` to the shared JSON, and state the precision in the report as `kinds total / candidates` (the kind counts summed, over `correction_candidates`). Never copy candidate text anywhere else.
3. Ask the user once which other machines to include. Every machine must count the same window, so pass this machine's `--since` along. For each machine, give the two ways in, then continue with whatever is in the exchange directory, without waiting:
   - **(a) Manual:** run the same counter there with this machine's `--since` and the default `--out`, follow its printed "Next:" line, and copy the shared JSON into this machine's `~/.cache/cct-self-review/`.
   - **(b) Peer session:** if a Claude session on that machine can be messaged, ask it to do (a) with this machine's `--since`, to keep the correction kinds generic agent-behaviour phrases (no project, repo, path or person names, and no words quoted from the corrections), and to reply with the shared JSON text only. Write that text into `~/.cache/cct-self-review/` as `<machine field of the JSON>-<date>.json`.
   - A machine column that appears in the previous report's table but not in this merge is named in the header as "not included this time".
4. Merge. Immediately before it, record the list of `*.json` files (not `*.local.json`) in `~/.cache/cct-self-review/`; step 9 archives exactly that list. Then run the counter with `--merge ~/.cache/cct-self-review/`. It reads every `*.json` there except `*.local.json`, and does not read subdirectories. For a repeated machine label the newest run is kept and the others are listed as `skipped: ...`; keep those lines. Paste the table unchanged, subject to step 7.
5. Read the Claude Code changelog (https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md) from the newest version named in the previous report's header (a first report covers the last 30 days of changelog entries), looking for features that make a toolkit rule redundant or newly possible.
6. Draft the whole report with the template below: header, table, items and since-last-report. Do not save it yet.
7. Privacy-check the draft. Look through all of it (header, table, items, machine labels and the `skipped:` file names) for project or repo names from the `.local.json` files, for a machine label or file name that identifies a machine or its user, and for any row label (a correction kind, for instance) that names a project, repo, path or person or quotes candidate text. Also remove any quoted or paraphrased correction-candidate text anywhere in the draft. Remove or rewrite generically anything that does. This overrides "paste unchanged" for that purpose only.
8. Write the checked draft to `docs/self-review/<YYYY-MM-DD>.md`.
9. Archive. Move exactly the list recorded in step 4, plus each file's `.local.json` if present, into `~/.cache/cct-self-review/merged-<YYYY-MM-DD>/`; that includes files the merge skipped as superseded. If that directory already exists, use `merged-<YYYY-MM-DD>-2`, `-3` and so on; never overwrite. A file that arrived after the listing stays in place; tell the user it was not in this report. The next merge does not read subdirectories, so a machine that is not re-run is reported as "not included this time" rather than with stale numbers.

## Report template

- **Header:** date, window, Claude Code versions and models seen, machine labels, the previous report or "first report", and one line that sessions whose records are on no included machine (for example cloud-hosted ones) are not counted.
- **Key numbers:** the merged table, then the Context Budget figures (harness-injected at session start, and at the end of bootstrap) from the bold newest-version column of the Context Budget table in `docs/architecture.md`.
- **At most 10 items**, ranked by cost saved or quality gained. Each gives the evidence, the change, the effect, the risk, and the files touched.
- **Since last report:** one line.

## Rule

Nothing is applied; each item waits for the user's approval of that item. The maintainer commits the report in the release PR. Anyone else keeps theirs in their own checkout, and may offer findings upstream via `/cct:contribute-upstream`.
