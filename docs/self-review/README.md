# Self-review report

`/self-review` turns your Claude Code session records into a short report: which models agents run on and what they cost in tokens, which hooks block and which skills and agents get used, which agent corrections recur, and which new Claude Code features could make a toolkit rule redundant. It proposes at most 10 items, each with evidence, change, effect, risk and files. Nothing is applied until you approve that item.

**What never leaves a machine.** The counter reads your session records locally. It writes two files: a shared JSON of counts (safe to copy to another machine) and a `.local.json` holding the raw correction candidates, which you keep where it is. Project and repo names are removed from the report before it is saved.

## One machine

In a toolkit checkout, run `/self-review` in Claude Code. It runs the counter, groups the corrections, reads the Claude Code changelog and writes `docs/self-review/<date>.md`.

## Several machines

On each other machine, in a toolkit checkout:

1. Run `python3 scripts/self-review-count.py --since <date>` (`python` on Windows), with the same `--since` as the machine that runs `/self-review`. Keep the default machine label; never use a hostname or user name.
2. Follow the `Next:` line it prints: group the corrections into generic behaviour kinds (no project, repo, path or person names, no quoted words) and add `correction_kinds` to the shared JSON.
3. Copy the shared JSON into `~/.cache/cct-self-review/` on the machine that runs `/self-review`. That one directory holds every machine's file; the counter writes there by default.

Then run `/self-review` there. It merges the directory; for a repeated machine label the newest run wins and the merge names the file it skipped. Afterwards it moves exactly the files it listed before merging (and their `.local.json`) into `merged-<date>/` there, never overwriting an earlier archive; a file that arrived in between stays put and is flagged. A machine you do not re-run then shows as "not included this time".

## The counter

`python3 scripts/self-review-count.py [flags]`

| Flag | Default |
|---|---|
| `--since YYYY-MM-DD` | 30 days ago |
| `--until YYYY-MM-DD` | no upper bound |
| `--root DIR` | `$CLAUDE_CONFIG_DIR/projects`, else `~/.claude/projects` |
| `--clone-root DIR` (repeatable) | the parent of the toolkit checkout |
| `--toolkit DIR` | the checkout the script lives in |
| `--machine LABEL` | `<os>-<6 hex of a hostname hash>`; keep the default, and never use a hostname or user name |
| `--out FILE` | `~/.cache/cct-self-review/<machine>-<today>.json` (the local file is the same name ending `.local.json`) |
| `--merge DIR` | merge every `*.json` in DIR except `*.local.json`; needs no session records |
| `--self-test` | run the built-in tests |

Sessions whose records are on no included machine (for example cloud-hosted ones) are not counted. Keep the report in your own checkout, or offer findings upstream with `/cct:contribute-upstream`.
