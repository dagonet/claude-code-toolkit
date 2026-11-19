# Self-review report

`/self-review` turns your Claude Code session records into a short report: which models agents run on and what they cost in tokens, which hooks block and which skills and agents get used, which agent corrections recur, and which new Claude Code features could make a toolkit rule redundant. It proposes at most 10 items, each with evidence, change, effect, risk and files. Nothing is applied until you approve that item.

**What never leaves a machine.** The counter reads your session records locally. It writes two files: a shared JSON of counts (safe to copy to another machine) and a `.local.json` holding the raw correction candidates, which you keep where it is. Project and repo names are removed from the report before it is saved.

## One machine

In a toolkit checkout, run `/self-review` in Claude Code. It runs the counter, groups the corrections, reads the Claude Code changelog and writes `docs/self-review/<date>.md`.

## Several machines

On each other machine, in a toolkit checkout:

1. Run `python3 scripts/self-review-count.py` (`python` on Windows).
2. Follow the `Next:` line it prints: group the corrections into behaviour kinds and add `correction_kinds` to the shared JSON.
3. Copy the shared JSON into the inbox of the machine that runs `/self-review`: `~/.cache/cct-self-review/inbox/`.

Then run `/self-review` there. It merges everything in the inbox; for a repeated machine label the newest run wins and the merge names the file it skipped.

## The counter

`python3 scripts/self-review-count.py [flags]`

| Flag | Default |
|---|---|
| `--since YYYY-MM-DD` | 30 days ago |
| `--until YYYY-MM-DD` | no upper bound |
| `--root DIR` | `$CLAUDE_CONFIG_DIR/projects`, else `~/.claude/projects` |
| `--clone-root DIR` (repeatable) | the parent of the toolkit checkout |
| `--toolkit DIR` | the checkout the script lives in |
| `--machine LABEL` | `<os>-<6 hex of a hostname hash>` |
| `--out FILE` | `~/.cache/cct-self-review/<machine>-<today>.json` (the local file is the same name ending `.local.json`) |
| `--merge DIR` | merge every `*.json` in DIR except `*.local.json`; needs no session records |
| `--self-test` | run the built-in tests |

Sessions whose records are on no included machine (for example cloud-hosted ones) are not counted. Keep the report in your own checkout, or offer findings upstream with `contribute-upstream`.
