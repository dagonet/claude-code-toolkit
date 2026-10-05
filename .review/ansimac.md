# Ledger: ANSI-C + macOS fixes (v4.4.0), feat/ansi-mac-fixes

Scratch review ledger. Delete after reading.

- **Design:** `docs/plans/2026-10-04-ansi-mac-design.md`, scope items 1–4. Item 5 (rows 25 and 30) is out of scope.
- **Base:** 2eab31b, which is v4.3.1 final (6b9b9d9) plus the design.
- **Draft PR:** #191.

## Commits (pushed to origin/feat/ansi-mac-fixes)

| sha | task | what |
|---|---|---|
| 59a4f9a | A | `gc_dollar_quote` (quote-aware POSIX awk). Called at the end of `gc_read_stdin` (guard-off still wins) and per script body in `gc_dir_rule` (git/gh word required). Adds V4 rows 2–37 (rows 25 and 30 not asserted). |
| 628d4ab | B | `gc_split_ops` (`tr` + awk gsub) at the 4 `&&` sites. BOM strip via `GC_BOM`. `sed -nE` in `a6_args` (#3) and no-push-main checkout/switch (#4). run-gate Gate-extra split via awk (#5). `LC_ALL=C` on the 16 KB body pipelines (#7). Adds V4 BSD-sed rows r40–r45. #6 was skipped (optional). |
| 9cdf2ae | A, review round 1 | Adds an `r` state for `${...}` (a `"${z:-$'..'}"` word was a fail-open). Skips `#` comments (an apostrophe in a comment hid a later `$'`). Adds rows r46–r51, including a guard-off row. |
| 0153530 | B, review round 1 | `grep -a` on both script-body sites (a NUL byte made GNU grep print nothing, so the body was hidden; this was a pre-existing fail-open). Adds rows r52–r55, which pin the `gc_seg_raw` split; checked against a mutant. |

**Diff:** 9 files, +222 / −18.
- `hooks/lib/git-cmd.sh` +67/−8.
- One line each in `gate-before-merge.sh`, `no-push-main.sh` and `run-gate.sh`.
- `scripts/test-hooks.sh` +94: block V4, delimited by `# ==== V4 begin` / `# ==== V4 end`.
- The four `user-level-reference/hooks` mirrors are cmp-identical. All files are LF only.

## V4 block

The block run is preamble lines 1–393, then the block, then the tally. It ran through the wrapper under each parser configuration:
- node: the real PATH.
- py: a symlink farm with node hidden.
- jq: a farm with node and python3 hidden.

| run | node | py | jq |
|---|---|---|---|
| RED, Task A (before the fix) | 55 pass / 156 fail (all 48 control cells pass) | – | – |
| RED, Task B, shim=1 (hooks unchanged) | 230 / 17 fail | 229 / 17 / 1 skip | 229 / 17 / 1 skip |
| **Final, shim=0** | **304 / 0 / 0** | **303 / 0 / 1** | **303 / 0 / 1** |
| **Final, shim=1** (BSD-sed emulation) | **304 / 0 / 0** | **303 / 0 / 1** | **303 / 0 / 1** |

- The single py/jq skip comes from the preamble (lines 1–393), not from V4.
- The Task B shim RED had 16 fail-open cells plus the design-#3 false refusal.
- Task A round 1 RED: 262 / 18 (r46, r47, r50).
- Task B round 1 RED:
  - With `gc_seg_raw` reverted (mutant), shim=1 fails r52–r54.
  - Before `-a`, r55 is red.
- **Shim.** `$SP/bsdsed/sed` is a perl wrapper that rewrites the script, then execs GNU sed:
  - `\n` in an s/// replacement becomes a literal `n`.
  - In BRE, `\|` becomes a literal `|`.
  - `\x` becomes `x`.
  - It reproduces all three of the design's real-Mac probes.

## Differential (v4.3.1 hooks vs final HEAD 0153530 hooks)

**Corpus.** 2,175 commands:
- design rows 1–37 plus 9 extra script forms;
- 435 literal fixture commands from the v4.3.1 suite;
- 600 sampled bash lines from tracked `*.md` files;
- 21 transcript commands;
- 500 sampled benign × gated chains (`&&`, `&&` without spaces, `;`, `|`, newline, `||`);
- 400 sampled `$'`/`$"` chains;
- tight, `cd`, subshell and `bash -c` forms;
- 80 PowerShell-tool forms.

**Grid.** 3 gates (pre-commit-test, no-push-main, gate-before-merge) × 2 fixtures (main with main protected; feature/x; `**Test**`/`**Gate**` false) × {node, py, jq, node+shim} = **52,200 cells**.

| config | NEW ALLOWS | NEW DENIES (cells) | class |
|---|---|---|---|
| node | **0** | 1,638 | all are intended `$'` refusals (344 distinct commands) |
| py | **0** | 1,638 | identical to node |
| jq | **0** | 1,638 | identical to node |
| node+shim | 12* | 2,119 | 1,747 intended `$'` refusals; 372 intended split/BOM fixes (155 distinct commands) |

\* All 12 shim allows are BSD **false refusals** of the design's #3/#4 kind that the ERE rewrite removes. In every one, GNU v4.3.1 also allows. Examples:
- `git merge --abort`, `--continue`, `--quit`;
- `git pull --ff-only origin main` (several variants);
- `git switch feature/x ; git merge feature/x`;
- a `git checkout -b X; ...; git push ...` chain.

Against the GNU v4.3.1 verdict there are 0 new allows.

**Unexpected new denies: 0.**

**Agreement checks:**
- The new hooks under the shim give the same verdict as under GNU in 13,050 / 13,050 cells.
- py and jq match node in every cell.

**Where the intended `$'` refusals come from:**
- design rows 2–23, 28, 29, 31, 32, 35, 37;
- generated `$'` chains;
- generated chains containing `bash e.sh` (a script body with `$'` plus git).

None come from the md, suite or transcript sources. The design's own one agent-shaped hit is the doc line `case "$p" in *$'\r')`; it is refused by design and is in the corpus as a generated form.

**Intended split/BOM fixes (shim):**
- `X && git pull|merge|push ...`;
- `echo hi &&git commit|push`;
- `ls && . ./c.sh`;
- `pwsh|powershell ... b.ps1` (BOM);
- PowerShell `...; git push origin main` chains.

## Full suite and consistency

- **Full suite:** `scripts/test-hooks.sh` was run via a wrapper, node, after `git fetch --tags`.
  - HEAD 0153530: **2890 passed, 8 failed, 4 skipped** (2902 assertions, 594 s).
  - The same 8 assertions **fail identically on the base 2eab31b** in this container: 2593 passed, 8 failed, 4 skipped (2605 assertions). The +297 assertions on HEAD are exactly V4.
  - The 8 are host-specific (Linux cloud container, root):
    - 6 `enforce-agent-contract` pipeline/R17 rows;
    - `#1 claude.md on a case-INSENSITIVE fs` (Linux filesystems are case-sensitive);
    - `FR2 bypass (hash-indirect)`.
  - None of these hooks calls a changed function. **The branch introduces 0 new failures.** The required "0 failed" is not reachable on this host.
- **Consistency:** `verify-template-consistency.sh` printed ALL CHECKS PASSED after every task commit (the implementers' runs, and the repo's own pre-commit **Test** on each commit).
- **Not run:** the parser matrix script (~90 min). The V4 block plus the differential cover all three parsers. Per CLAUDE.md, run one matrix before release.

## Reviews (opus)

**Task A**
- Round 0, CHANGES REQUESTED:
  - I1: `$'` inside `"${...}"` was a fail-open.
  - Ruling (b): add `#`-comment skipping.
  - Minor: residuals documented, guard-off row, helper comment.
- Round 1: **APPROVED**.

**Task B**
- Round 0, CHANGES REQUESTED:
  - The `gc_seg_raw` split was not pinned by any row; the mutant was a real BSD fail-open.
  - A NUL byte hid a script body (pre-existing).
- Round 1: **APPROVED**.

**Open Minor items (not blocking):**
- No Gate-extra row for run-gate #5. A controller probe under the shim confirms the old `sed -E` split collapsed the legs (`truenbash x.shnecho ok`) and the awk split yields 3 legs.
- `gc_segments` strips quotes before splitting, so for `x &"&" y` the segment indices drift (pre-existing).

**Documented residuals of `gc_dollar_quote`:**
- a heredoc body with an odd number of apostrophes can hide a later `$'`;
- a `case` label's `)` inside `"$(...)"` closes the `$(` early;
- `$$'x'` is refused (errs closed);
- a script body that encodes the git word itself passes the body check;
- backticks inside `"..."` close crudely (errs closed).

## Merge hotspots (for the v4.4 combine)

**Functions touched in `hooks/lib/git-cmd.sh`:**
- `gc_read_stdin`: tail, a new refusal after `gc_protect_c_paths`.
- New `gc_dollar_quote`: right after `gc_read_stdin`.
- New `gc_split_ops`: just above `gc_segments`.
- `gc_segments`, `gc_seg_quoted`, `gc_seg_raw`, `gc_text_has_gated`: the splitter line.
- `gc_ps_script_bodies`: BOM sed plus `LC_ALL=C grep -av`.
- `gc_script_body`: `LC_ALL=C grep -av`.
- `gc_dir_rule`: the body `$'` check inside the body loop.

**Other files:**
- `hooks/gate-before-merge.sh`: `a6_args`.
- `hooks/no-push-main.sh`: the `mvargs` sed.
- `hooks/run-gate.sh`: the `RG_LEGS` split.
- `scripts/test-hooks.sh`: the V4 block, inserted between `# ---- end v4.3.1 S6b` and the tally.

**After the combine:** re-check design rows 25 and 30 against the v4.3.2 Task 6b changes.

## CHANGELOG paragraph (for the v4.4.0 entry; CHANGELOG.md not edited here)

> **ANSI-C quoting and macOS portability in the git gates.** All three git gates now refuse any real `$'...'` or `$"..."` word. Before this, `git $'\x63ommit'`, `git push origin $'ma\x69n'`, `gh pr $'merge'`, `$'\x73h' c.sh` and similar forms were fail-open: every gate that reads a word exactly was blind to them.
> - **Where the check runs.** `gc_dollar_quote`, a quote-aware POSIX awk scan, runs once at the end of `gc_read_stdin`, before any fast exit. It runs again per script body, where it refuses only when the body also holds a git or gh word. It sees `$(...)`, backticks and `${...}` inside double quotes, and skips `#` comments.
> - **False positives by design.** `IFS=$'\n'` and `git log --format=$'%h\t%s'` are refused too. The message names the remedy: use plain quotes, and printf for escapes. The `.claude/git-guard-off` escape hatch still wins.
> - **macOS.** BSD sed writes a literal `n` for `\n` in a replacement, so `a && b` was one segment on macOS. That let `git checkout x && git push origin main`, `true&&git commit` and `echo hi && gh pr merge 5` through. A single `gc_split_ops` (`tr` + awk) now splits at all four sites.
> - **Smaller portability fixes.**
>   - The `.ps1` BOM strip reuses `GC_BOM` (BSD sed has no `\xHH`).
>   - `a6_args` and the checkout/switch parse use ERE alternation (BSD BRE has no `\|`; this falsely refused `git pull --ff-only origin main` and `git merge --abort`).
>   - The run-gate **Gate extra** split uses awk.
>   - The 16 KB body pipelines run under `LC_ALL=C` with `grep -a`, so a NUL byte no longer hides a script body (pre-existing).
> - **Verification.** A 2,175-command differential against v4.3.1 across node, python3 and jq, plus BSD-sed emulation, found 0 new allows. Block V4 in `test-hooks.sh` carries the design's verdict-table rows 2–37 and the BSD-sed rows.
> - **Known limits.** Rows 25 and 30 (`m\ain`, `co\mmit`) are out of scope here. `gc_dollar_quote` residuals: a heredoc body with an odd number of apostrophes; a `case` label inside `"$(...)"`.
