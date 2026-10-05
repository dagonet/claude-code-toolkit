# Hook equivalence corpus

`corpus.tsv` is the input of `scripts/hook-equivalence.sh`, the safety net of the
hook-slimming Phase C (v4.4.0): every payload runs through the hook set at
`PHASEC_BASE` (old, `git archive`) and through the working tree (new), as Claude
Code would run it, and any change of decision is reported. Phase C may change how
hooks are registered and how fast they exit; it may not change what they decide.

## Corpus format

One row per line: `id<TAB>event<TAB>tool<TAB>payload`. Lines starting with `#` are
comments. `tool` is what registration matchers are tested against (for
`SessionStart` it is the source). `payload` is the stdin of the hook, verbatim.
Tokens the harness expands before running:

| token | becomes |
|---|---|
| `@CWD@` | the scenario's temp project directory (the payload `cwd` is never this checkout) |
| `@BOM@` | the UTF-8 byte-order mark |
| `@REP:<n>:<text>@` | `<text>` repeated n times (the 20 kB command, the 11,999-char outputs) |
| `@EMOJI:<n>@` | n copies of U+1F600 (a four-byte character, two UTF-16 units) |

125 rows. Ids by group: `bp01-23` push and branch, `cm01-06` commit and merge
gate, `sr01-17` secret reads, `hs01-08` hang shapes, `ps01-08` PowerShell,
`ag01-05` Agent, `ew01-04` Edit/Write, `pt01-04` PostToolUse output sizes (11,999
and 12,001 chars, 6,001 emoji, 3,000 `é` escapes), `eh01-14` escapes and
harmless commands, `mf01-06` malformed input (empty stdin, BOM, two documents,
array command, two documents led by a heredoc-into-file / by `cat .env`). Extras: `ss01` SessionStart, `rd01-03` Read (`rd01` is a 2,000-line
file, so `read-size-gate` rewrites it), `ok01-12` harmless commands, `ew05-06`
Edit/Write from a subagent (`agent_id`), `bd01-04` build-runner commands (`bd01`
from a subagent). Registered protections the first cut missed: `mc01-02` the
MCP merge tools (gate-before-merge's MCP matcher), `sa01-04` SubagentStop with
and without a valid agent contract (`tr-ok.jsonl` / `tr-bad.jsonl` are written
into every scenario project; `sa03` has no transcript, `sa04` is a `notify`
agent), `pe01` PostToolUse Write (post-edit-build), `up01` UserPromptSubmit (the
inline date hook; only its class is compared, so the clock does not matter).
Rows whose expected class is `allow` are deliberate: `sr13`,
`sr14`, `hs03`, `hs07`, `hs08`, `bp19-22` and the harmless rows prove the
protections are not simply denying everything.

## What the harness does

- **Registrations are read, not assumed.** `settings.json` (user-level in a temp
  `HOME`, project, `settings.local.json`) is parsed by python3; a registration is
  selected by event and matcher (missing, empty or `*` = all; otherwise a regex
  full match of the tool name), then run in its own form: shell form as
  `/bin/sh -c`, exec form as an argv with `${CLAUDE_PROJECT_DIR}` substituted. The
  user-level `@BASH@` / `@HOOKS@` tokens are substituted directly (the absolute
  bash path and the row's own `~/.claude/hooks`) when a set's settings carry them.
  Each hook run has a 60 s timeout and a fresh `TMPDIR`.
- **Classes:** `deny` (exit 2, or JSON deny / `decision: block`) > `ask` >
  `context` (additionalContext or updatedToolOutput; any stdout on PostToolUse and
  SessionStart) > `allow`. A non-zero exit other than 2 is a non-blocking error:
  class `allow`, annotated `allow*`, printed as a `NOTE` only when it is the sole
  difference. **Reason category** = the set of hook basenames that denied. The
  name comes from the registration (the script it runs), not from message wording,
  so a reworded block message is not a change. An `updatedInput` /
  `updatedToolOutput` emission is compared too (hook name plus a digest of the
  content, with the sandbox path and the spill-log name normalised).
- **Scenarios**, each in a normal and a *missing* mode (every `hooks/*.sh` and
  `~/.claude/hooks/*.sh` renamed to `*.sh.offline`, `lib/` kept, old and new alike):
  S1 a plain git repo, user-level hooks only; S2 a project bootstrapped by THAT
  set's own `setup-project.sh --variant general` (so the bootstrap itself is
  exercised, not imitated), plus user-level hooks; S3 a temp project holding that
  set's root `.claude/settings.json` and `hooks/` (it registers only some hooks:
  the C5 step-aside bypass fixture); S4 the S2 project with NO user-level hooks
  or settings, so a regression of a PROJECT registration is not masked by the
  user-level copy of the same guard (a reason category is a name set). All four are git repos on `main` with a
  staged change, `push.sh` / `push.ps1` scripts that push main, and `.env*`
  files; `PROJECT_CONTEXT.md` carries Test and Gate = `true`, so no real suite
  runs. Every row runs in its own copy of the scenario, rows run in parallel, and
  the output order is deterministic.
- **Parser configurations** (`--config`): `full` (normal PATH), `python3` (a
  whitelist shim directory of symlinks with no `node` and no `jq`), `jq` (no
  `node`, no `python3`). The shim tool list is generous (coreutils, git, grep,
  sed, awk, timeout, ...). Each restricted run self-checks with `command -v` (the
  parser it keeps must be found and run, the others must not be found) and exits
  2 if the restriction did not apply; any `command not found` in a hook's stderr
  (an incomplete shim) exits non-zero as `ENV-INCOMPLETE`.
- **Tally rule:** every normal scenario (S1-S4) must have at least 25 `deny` and
  25 `allow` rows, or the run fails: a corpus that all allows proves nothing. The
  floor is checked on UNCHUNKED runs only: a chunked (`--only`) run does not
  check it, and neither does missing mode, where nearly everything denies by
  design.
- **Base:** the old side is `--base <sha>`, else `PHASEC_BASE=` in the git-ignored
  `.superpowers/sdd/2026-10-04-hook-slimming/base.txt` if present, else the
  committed `base.sha` (a fresh checkout runs without the ignored file).
- **Matchers:** Claude Code tests a matcher as a regex and the harness uses
  `fullmatch`; that is equivalent for the current `A|B` matchers.

Output: `DIFF <scenario> <config> <id>: old=<class>{<cats>} new=<class>{<cats>}`
per difference, `TALLY` lines, `WALL`, and a last line
`EQUIVALENCE: <n> decision changes`. Exit 0 only when n = 0 and the tally holds.
`--list 1` prints every row's result.

```
bash scripts/hook-equivalence.sh --config full            # also: --config python3, --config jq
bash scripts/hook-equivalence.sh --config full --mode normal --only 'bp*'
bash scripts/hook-equivalence.sh --config full --new-root <scratch copy of the tree>
```

## Accepted diffs

`accepted.tsv` (columns: id, scenario glob, config, reason) lists differences that
are known and accepted. A DIFF matching an entry is accepted only when the new
result is strictly more restrictive: the class goes allow/allow*/context -> deny
(or ask -> deny), or stays deny with a strict superset of the old deny set. It
prints `ACCEPTED-STRICTER ... (<reason>)`; a match that is not stricter stays a
DIFF (`DIFF (accepted entry does not apply: not stricter)`), so the file can never
accept a new allow. `NEW-ALLOWS: <n>  NEW-DENIES: <m>` counts every row-level
loosening / tightening, accepted or not. The last line is
`EQUIVALENCE: <n> decision changes` (n excludes accepted rows, which are then
counted as `(<k> accepted stricter)`); exit 0 only when n = 0.

## Known gaps

- Missing mode is all-or-nothing (every project and user-level script is renamed
  away at once), so the C5 case "global missing, project copy present and
  registered" is not exercised.
- A set that ships `scripts/render-user-hooks.sh` (the NEW set, since Task 8) has its user
  settings rendered by that script's `--print` (once per template, with `RUH_TEST_BASH` = the
  harness's bash), so the renderer's real output is what runs. The OLD set has no renderer;
  the harness keeps its direct `@BASH@` / `@HOOKS@` substitution for it.

## Measured (Linux, 4 cores, 4 workers, base a56ca34 = new)

| run | rows x scenario-modes | wall |
|---|---|---|
| `--config full` (normal + missing) | 123 x 8 | 384 s |
| `--config python3` (normal + missing) | 123 x 8 | 352 s |
| `--config jq` (normal + missing) | 123 x 8 | 239 s |

All three: `EQUIVALENCE: 0 decision changes`. Normal-mode tallies (deny / allow;
context rows are the rest):
full S1 47/73, S2 63/56, S3 54/66, S4 63/57; python3 S1 47/75, S2 56/66, S3
54/68, S4 56/67; jq S1 48/74, S2 57/65, S3 55/67, S4 57/66.

## Self-test of the harness (recorded at its introduction)

(a) new = old (the working tree held no Phase C change): `EQUIVALENCE: 0 decision
changes`, exit 0, in all three configurations (above).

(b) Control. A scratch copy of the tree with `exit 0` inserted as the first line
after the shebang of `hooks/no-push-main.sh` and `user-level-reference/hooks/no-push-main.sh`
(the tracked hooks are never touched), passed as `--new-root`:

```
S=$(mktemp -d)
tar -C <repo> --exclude=.git --exclude=server --exclude=mcp-servers --exclude=.superpowers --exclude=docs -cf - . | tar -C $S -xf -
sed -i '1a exit 0' $S/hooks/no-push-main.sh $S/user-level-reference/hooks/no-push-main.sh
bash scripts/hook-equivalence.sh --config full --mode normal --new-root $S --only 'bp*'
```

Result: 68 `DIFF` lines, 17 per scenario (S1: the user-level hook is the only push
guard, so the class falls deny -> allow; S2, S3, S4: `gate-before-merge` still
denies, so the class stays `deny` and the reason category loses `no-push-main`),
`EQUIVALENCE: 68 decision changes`, exit 1.

(c) Control for the project registrations (S4). A scratch copy where ONLY
`templates/general/.claude/settings.json` changes: the missing-script branch of
the `deny-secret-reads` registration goes from `exit 2` to `exit 0`:

```
bash scripts/hook-equivalence.sh --config full --mode missing --new-root <scratch> --only 'sr*'
```

Result: 17 `DIFF` lines, all in S4m (old category carries `deny-secret-reads`, new
does not); S2m, which still has the user-level copy, hides it - exactly why S4
exists. `EQUIVALENCE: 17 decision changes`.
