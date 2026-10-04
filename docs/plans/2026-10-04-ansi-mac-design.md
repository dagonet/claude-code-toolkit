# ANSI-C quoting and macOS portability in the git gates — design

Date: 2026-10-04
Status: **approved by the user 2026-10-04 22:58**, through dashboard question #5: "Yes, fix both in v4.4". Ships in **v4.4.0**.
Source: a read-only spike on `feat/v4.3.1` @ `6b9b9d9`. This file is that spike's report, unchanged apart from this header and the scope section.

## Scope approved for v4.4.0

1. **Q1, option C.** Any real `$'...'` or `$"..."` word is cannot-determine and is refused (see "Options" below):
   - `gc_dollar_quote`, a quote-aware awk scan, is called once at the end of `gc_read_stdin`.
   - It is called again per script body in `gc_dir_rule`. There it refuses only if the body also has a git or `gh` word.
   - Test rows 2–37 from the verdict table go into `scripts/test-hooks.sh`.
2. **Q2 #1.** `gc_split_ops`, one helper for all four `sed 's/&&/\n/g'` sites (`gc_segments`, `gc_seg_quoted`, `gc_seg_raw`, `gc_text_has_gated`): `tr '|;' '\n\n' | awk '{gsub(/&&/,"\n")}1'`. It keeps the segment index alignment.
3. **Q2 #2.** The BOM strip `LC_ALL=C sed "1s/^$GC_BOM//"`, reusing `GC_BOM`.
4. **Cheap, closed-direction portability fixes in the same pass:**
   - #3 `gate-before-merge.sh` `a6_args` and #4 `no-push-main.sh` checkout/switch: `sed -nE` with ERE alternation.
   - #5 `run-gate.sh` **Gate extra** leg split: the same awk gsub as #1.
   - #7: `LC_ALL=C` on the 16 KB body pipeline.
   - #6 (`\b`) is optional.
5. **Out of scope.** Rows 25 and 30 (backslash inside a word: `m\ain`, `co\mmit`). The v4.3.2 integration (Task 6b and its review rounds) already addresses `com\mit` and backslashes in push refspecs. Re-check both rows after the v4.4 combine.
6. **Real-Mac confirmation** before the release, if a Mac is available: `printf 'a&&b\n' | sed 's/&&/\n/g' | wc -l` prints `1` on macOS. The awk form is correct on GNU and BWK awk either way.

---

Method: each gate hook was run directly with a PreToolUse JSON payload, using the same `mkjson` shape as `scripts/test-hooks.sh`.

- **Fixture repos:** a **main** fixture on `main` and a **feat** fixture on `feature/x`. Both have `**Test**: false` and `**Gate**: false`.
- **Scripts in each fixture:**
  - `c.sh` holds `git commit -m x` and `git push origin main`
  - `e.sh` holds `git $'\x63ommit' -m x` and `git push origin $'ma\x69n'`
  - `b.ps1` is a BOM-prefixed `git push origin main`
- **Tools:** Linux bash 5.2.21, mawk 1.3.4, GNU sed and grep. BWK awk 20231127 stood in for macOS awk.

## Q1: ANSI-C quoting (`$'...'`), plus `$"..."` and backslashes inside words

### Today's verdicts (measured)

**ALLOW** in bold marks a fail-open: the gate that owns this verb allowed it. The other gates allowing is correct.

| # | command | pre-commit main | pre-commit feat | no-push-main main | no-push-main feat | gate-before-merge main | gate-before-merge feat | verdict today | prototype |
|---|---|---|---|---|---|---|---|---|---|
| 1 | `git commit -m x` | BLOCK | BLOCK | allow | allow | allow | allow | closed | closed |
| 2 | `git $'\x63ommit' -m x` | **ALLOW** | **ALLOW** | allow | allow | allow | allow | **FAIL-OPEN** | closed |
| 3 | `git $'commit' -m x` | BLOCK | BLOCK | allow | allow | allow | allow | closed | closed |
| 4 | `git $'\143ommit' -m x` | **ALLOW** | **ALLOW** | allow | allow | allow | allow | **FAIL-OPEN** | closed |
| 5 | `$'git' commit -m x` | BLOCK | BLOCK | allow | allow | allow | allow | closed | closed |
| 6 | `$'\x67it' commit -m x` | **ALLOW** | **ALLOW** | allow | allow | allow | allow | **FAIL-OPEN** | closed |
| 7 | `$'\x73h' c.sh` | **ALLOW** | **ALLOW** | **ALLOW** | **ALLOW** | **ALLOW** | **ALLOW** | **FAIL-OPEN** | closed |
| 8 | `$'sh' c.sh` | **ALLOW** | **ALLOW** | **ALLOW** | **ALLOW** | **ALLOW** | **ALLOW** | **FAIL-OPEN** | closed |
| 9 | `bash $'c.sh'` | **ALLOW** | **ALLOW** | **ALLOW** | **ALLOW** | **ALLOW** | **ALLOW** | **FAIL-OPEN** | closed |
| 10 | `bash $'\x63.sh'` | **ALLOW** | **ALLOW** | **ALLOW** | **ALLOW** | **ALLOW** | **ALLOW** | **FAIL-OPEN** | closed |
| 11 | `git push origin main` | allow | allow | BLOCK | BLOCK | BLOCK | BLOCK | closed | closed |
| 12 | `git push origin $'ma\x69n'` | allow | allow | **ALLOW** | **ALLOW** | **ALLOW** | **ALLOW** | **FAIL-OPEN** | closed |
| 13 | `git push origin $'main'` | allow | allow | **ALLOW** | **ALLOW** | **ALLOW** | **ALLOW** | **FAIL-OPEN** | closed |
| 14 | `git $'push' origin main` | allow | allow | BLOCK | **ALLOW** | BLOCK | **ALLOW** | **partly open** | closed |
| 15 | `git $'\x70ush' origin main` | allow | allow | **ALLOW** | **ALLOW** | **ALLOW** | **ALLOW** | **FAIL-OPEN** | closed |
| 16 | `git push origin $'HEAD:ma\x69n'` | allow | allow | **ALLOW** | **ALLOW** | **ALLOW** | **ALLOW** | **FAIL-OPEN** | closed |
| 17 | `gh pr merge 5` | allow | allow | allow | allow | BLOCK | BLOCK | closed | closed |
| 18 | `gh pr $'merge' 5` | allow | allow | allow | allow | **ALLOW** | **ALLOW** | **FAIL-OPEN** | closed |
| 19 | `gh pr $'\x6derge' 5` | allow | allow | allow | allow | **ALLOW** | **ALLOW** | **FAIL-OPEN** | closed |
| 20 | `gh $'pr' merge 5` | allow | allow | allow | allow | **ALLOW** | **ALLOW** | **FAIL-OPEN** | closed |
| 21 | `git $'merge' feature/x` | allow | allow | allow | allow | BLOCK | allow | closed | closed |
| 22 | `git $'\x6derge' feature/x` | allow | allow | allow | allow | **ALLOW** | allow | **FAIL-OPEN** | closed |
| 23 | `git commit -m $'line1\nline2'` | BLOCK | BLOCK | allow | allow | allow | allow | closed | closed |
| 24 | `git push origin "ma"'in'` | allow | allow | BLOCK | BLOCK | BLOCK | BLOCK | closed | closed |
| 25 | `git push origin m\ain` | allow | allow | **ALLOW** | **ALLOW** | **ALLOW** | **ALLOW** | **FAIL-OPEN** | still open |
| 26 | `sh c.sh` | BLOCK | BLOCK | BLOCK | BLOCK | BLOCK | BLOCK | closed | closed |
| 27 | `bash c.sh` | BLOCK | BLOCK | BLOCK | BLOCK | BLOCK | BLOCK | closed | closed |
| 28 | `git $"commit" -m x` | BLOCK | BLOCK | allow | allow | allow | allow | closed | closed |
| 29 | `git push origin $"main"` | allow | allow | **ALLOW** | **ALLOW** | **ALLOW** | **ALLOW** | **FAIL-OPEN** | closed |
| 30 | `git co\mmit -m x` | **ALLOW** | **ALLOW** | allow | allow | allow | allow | **FAIL-OPEN** | still open |
| 31 | `bash e.sh` (script body uses `$'..'`) | **ALLOW** | **ALLOW** | **ALLOW** | **ALLOW** | BLOCK | **ALLOW** | **partly open** | closed |
| 32 | `echo "$(git $'\x63ommit' -m x)"` | **ALLOW** | **ALLOW** | allow | allow | allow | allow | **FAIL-OPEN** | closed |
| 33 | `git commit -m "$(printf 'a\nb')"` | BLOCK | BLOCK | allow | allow | allow | allow | closed | closed |
| 34 | `grep -n "foo$" seed.txt && git status` | allow | allow | allow | allow | allow | allow | control (should allow) | allow |
| 35 | `IFS=$'\n'; echo hi` | allow | allow | allow | allow | allow | allow | control (should allow) | **BLOCK (false positive)** |
| 36 | `echo '$'"'"'x'"'"` | allow | allow | allow | allow | allow | allow | control (should allow) | allow |
| 37 | `git log --format=$'%h\t%s' -1` | allow | allow | allow | allow | allow | allow | control (should allow) | **BLOCK (false positive)** |

What the table shows:

- **Pattern.** An escape-free `$'word'` in **verb** position (rows 3, 5, 28) is caught by accident: quote stripping turns `$'commit'` into `$commit`, and pre-commit's verb test is a substring match. Once a gate has to read the word **exactly**, none of them do: branch names (12, 13, 16, 29), `gh pr` words (18–20), the script runner and script path (7–10), and anything with `\x`, `\NNN` or `$(...)` (2, 4, 6, 15, 19, 22, 32).
- **Script bodies (row 31).** The script-body scan has the same blind spot.
- **Not ANSI-C, same family (rows 25, 30).** A backslash inside a word is also fail-open in v4.3.1 (see Scope item 5).

### Options

False-positive counts come from a corpus of 23,309 command lines. Only `$'` / `$"` inside a real quoting context is counted.

| corpus | lines | contain `$'` | crude "`$'` + git/gh/sh word in segment" | **any real `$'..'`/`$".."` (recommended rule)** | real `$'`/`$"` + git/gh/runner word, quote-aware (rule R) |
|---|---|---|---|---|---|
| `test-hooks.sh` mkjson fixture commands | 1,052 | 0 | 0 | **0** | 0 |
| fenced/inline bash in tracked `*.md` | 5,011 | 3 | 0 | **1** | 0 |
| Bash tool commands in local transcripts | 42 | 3 | 3 | **0** | 0 |
| repo `*.sh` lines (hand-written script code) | 17,205 | 110 | 2 | **49** | 5 |
| **agent-shaped total (first three rows)** | **6,105** | 6 | 3 | **1** | **0** |

The one agent-shaped hit for the recommended rule is a doc line: `for p in "${PATHS[@]}"; do case "$p" in *$'\r') ... esac; done`.

**A. Crude substring.** Refuse when a segment contains `$'` and a git/gh/script-runner word.
- About 5 lines.
- False positives: 5 overall, 3 agent-shaped. It is not quote-aware.
- It misses `$'\x67it' commit` and `$"..."`.
- Not fail-closed. **Rejected.**

**B. Decode `$'...'`, then requote the result and feed it to the existing walk.**
- About 60–80 lines in bash 3.2.
- It cannot be made fail-closed by construction. The decoder runs in the hook's bash, while the command runs in the Bash tool's shell (zsh, or another bash version). The two differ on `\u` and `\c`.
- **Rejected.**

**C. (recommended, APPROVED) Any real `$'...'` or `$"..."` word is cannot-determine and is refused.**
- **Mechanism.** `gc_dollar_quote` is a quote-aware awk scan:
  - it skips `'...'`;
  - it skips `"..."`, except inside `$(` and backticks;
  - it skips backslash-escaped characters;
  - it reports any `$` followed by a quote.
- **Where it is called.**
  - Once at the end of `gc_read_stdin`, so all three gates refuse before any fast exit. Pre-commit's nocasematch fast exit would otherwise skip `git $'\x63ommit'`.
  - Again per script body in `gc_dir_rule`. There it refuses only if the body also has a git or `gh` word, because scripts use `$'\n'` routinely.
- **Size.** About 35 added lines, 28 of them code.
- **Effect on the verdict table.**
  - It closes every `$'`/`$"` row (2, 4, 6–10, 12–16, 18–20, 22, 29, 31, 32), in all three gates on both fixtures.
  - Rows 3, 5, 21, 23 and 28 now block for the right reason.
- **False positives.** 1 in 6,105 agent-shaped commands. Rows 35 and 37 are false positives by design. The refusal message names the remedy: plain quotes, with `printf` for escapes.
- **Portability.** It needs only `case`, `printf` and awk, so it runs on bash 3.2. A 37-row probe gave identical verdicts under mawk and BWK awk.
- **Parser matrix.** No parser-dependent code is added. Like any change to `git-cmd.sh`, it still needs one matrix run before release.
- **Residuals (documented).**
  - A script body that encodes the git word itself passes the body check.
  - Backticks inside `"..."` are scanned with only crude closing. This errs closed, never open.
- **Fallback (not the default): rule R.** It refuses only with a git/gh/runner word present, or with `$'` in command position.

## Q2: macOS / BSD static audit of `hooks/*.sh` and `hooks/lib/*.sh`

**How each row was checked:**
- **"Emulated"** means the verdict was measured on Linux with a PATH shim that reproduces BSD sed's behaviour.
- **"Probe"** gives the one-liner to run on a real Mac.

| # | file:line (at 6b9b9d9) | construct | what differs on macOS | direction | evidence | simplest portable fix |
|---|---|---|---|---|---|---|
| 1 | `hooks/lib/git-cmd.sh:492` (`gc_segments`), `:515` (`gc_seg_quoted`), `:533` (`gc_seg_raw`), `:757` (`gc_text_has_gated`) | `sed 's/&&/\n/g'` | BSD sed writes a literal `n` for `\n` in the replacement, so `a && b` becomes **one** segment `a n b`. | **FAIL-OPEN** | Emulated, measured. All 3 gates allow `git checkout feature/x && git push origin main` and `true&&git push origin main`. Pre-commit skips the Test on `true&&git commit -m x`. gate-before-merge allows `echo hi && gh pr merge 5`. | One helper at all four sites: `gc_split_ops() { tr '\|;' '\n\n' \| awk '{gsub(/&&/,"\n")}1'; }`, identical on mawk and BWK awk. |
| 2 | `hooks/lib/git-cmd.sh:604` (`gc_ps_script_bodies`) | `LC_ALL=C sed '1s/^\xEF\xBB\xBF//'` | BSD sed has no `\xHH` escape, so the BOM stays and line 1's command word is not recognised. | **FAIL-OPEN** (narrow) | Emulated, measured: `pwsh ./b.ps1` goes from BLOCK to allow. | `LC_ALL=C sed "1s/^$GC_BOM//"` |
| 3 | `hooks/gate-before-merge.sh:202` (`a6_args`) | BRE `\([[:space:]]\|\$\)` | GNU BRE `\|` | closed (false positive) | Emulated: `git pull --ff-only origin main` is refused. | `sed -nE "s/.*[[:space:]]$2([[:space:]]\|\$)/\1/p"` |
| 4 | `hooks/no-push-main.sh:130` | BRE `\(checkout\|switch\)\([[:space:]]\|$\)` | GNU BRE `\|` | closed (latent) | Emulated: no verdict change. | `sed -nE 's/.*[[:space:]](checkout\|switch)([[:space:]]\|$)/\2/p'` |
| 5 | `hooks/run-gate.sh:369` | `sed -E 's/[[:space:]]*&&[[:space:]]*/\n/g'` | same `\n` problem | closed (the gate goes red when **Gate extra** is set) | Emulated split string | same awk gsub as #1 |
| 6 | `hooks/gate-before-merge.sh:889` | `grep -qE '\bgh...\b'` | `\b` is an ERE extension | none observed | Emulated worst case | optional: the `no-push-main.sh:71` form |
| 7 | `hooks/lib/git-cmd.sh:604`, `:688` (`head -c 16384` feeding `grep`/`sed`/`tr`) | multibyte cut | BSD tools may reject an invalid UTF-8 tail | possibly OPEN (needs a probe) | Static | `LC_ALL=C` on the body pipeline |
| 8 | awk programs | BWK awk | — | none | Measured with BWK awk: identical | none |
| 9 | bash 3.2 constructs | — | none found | none | Static | one Mac run of `test-hooks.sh` under `/bin/bash`, if possible |
| 10 | `stat -c`, `sha256sum`, `mktemp`, `find`, `ps`, padded `wc -l` | GNU spellings | each already has a fallback | none | Documentation and local checks | none |

**Real-Mac probes:**
- `printf 'a&&b\n' | sed 's/&&/\n/g' | wc -l` — GNU prints 2, macOS 1.
- `printf 'ab\n' | sed 's/a\|b/X/g'` — GNU prints `XX`, BSD `ab`.
- `printf '\357\273\277x\n' | LC_ALL=C sed '1s/^\xEF\xBB\xBF//' | od -c | head -1` — the BOM is still present on BSD.
