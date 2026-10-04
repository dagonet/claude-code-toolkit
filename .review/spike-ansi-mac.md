# Spike: ANSI-C quoting and macOS portability in the git gates

**Scratch report. Delete it after reading.** This was a read-only spike on `feat/v4.3.1` @ `6b9b9d9`. No tracked file was changed. The prototype and all probes live in the session scratchpad. Probes ran on Linux (bash 5.2.21, mawk 1.3.4, GNU sed/grep). BWK awk 20231127 (`original-awk`) was installed to stand in for macOS awk.

Method: each gate hook was run directly with a PreToolUse JSON payload, using the same `mkjson` shape as `scripts/test-hooks.sh`. There were two scratch fixture repos:

- a **main** fixture, checked out on `main`
- a **feat** fixture, checked out on `feature/x`

Both fixtures have `**Test**: false` and `**Gate**: false`. A pre-commit `BLOCK` therefore means either the Test ran and failed or the hook refused. Both outcomes keep the commit out.

Each fixture also contains three scripts:

- `c.sh` holds `git commit -m x` and `git push origin main`
- `e.sh` holds `git $'\x63ommit' -m x` and `git push origin $'ma\x69n'`
- `b.ps1` is a BOM-prefixed `git push origin main`

Side note: this repo's own gates were live on my Bash tool the whole time. They correctly refused my first probe script, `git -C $d commit` ("cannot DETERMINE the -C target"). The fixture seed commits were therefore made with `git commit-tree` + `update-ref`, and gated text went into files through the Write tool. No hook was bypassed and no `git-guard-off` was created.

---

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
- **Script bodies (row 31).** The script-body scan has the same blind spot, so a scanned script can carry an encoded verb.
- **Not ANSI-C, same family (rows 25, 30).** A backslash inside a word (`m\ain`, `co\mmit`) is also fail-open today. Shell quote removal drops it, the gates don't. The T2-3a fix covers only the `git` word itself. Neither option below closes these two rows, so they need their own backlog item.

### Options

False-positive counts come from a corpus of 23,309 command lines. Only `$'` / `$"` inside a real quoting context is counted.

| corpus | lines | contain `$'` | crude "`$'` + git/gh/sh word in segment" | **any real `$'..'`/`$".."` (recommended rule)** | real `$'`/`$"` + git/gh/runner word, quote-aware (rule R) |
|---|---|---|---|---|---|
| `test-hooks.sh` mkjson fixture commands (the existing adversarial corpus) | 1,052 | 0 | 0 | **0** | 0 |
| fenced/inline bash in tracked `*.md` (commands agents are told to run) | 5,011 | 3 | 0 | **1** | 0 |
| Bash tool commands in local transcripts (this session; no others on the host) | 42 | 3 | 3 | **0** | 0 |
| repo `*.sh` lines (hand-written script code, not agent one-liners) | 17,205 | 110 | 2 | **49** | 5 |
| **agent-shaped total (first three rows)** | **6,105** | 6 | 3 | **1** | **0** |

The one agent-shaped hit for the recommended rule is a doc line: `for p in "${PATHS[@]}"; do case "$p" in *$'\r') ... esac; done`. The test-hooks corpus contains no `$'` at all, which means no fixture row exercises ANSI-C quoting today.

**A. Crude substring.** Refuse when a segment contains `$'` and a git/gh/script-runner word.
- About 5 lines.
- False positives: 5 overall, 3 agent-shaped. It is not quote-aware, so `grep 'x$' f && git ...` trips it.
- It misses `$'\x67it' commit`, where no git word is visible, and `$"..."`.
- Not fail-closed. **Rejected.**

**B. Decode `$'...'`** (`\xHH`, `\NNN`, `\0NNN`, `\uXXXX`, `\UXXXXXXXX`, `\cX`, `\e`/`\E`, `\a\b\f\n\r\t\v`, `\\ \' \" \?`), then requote the result and feed it to the existing walk.
- About 60–80 lines in bash 3.2. `printf %b` alone is wrong: it needs a leading 0 on octal, and bash 3.2's `printf %b` has no `\u`.
- The decoded text can contain `'`, `;` or newlines, so it must be requoted to stay a single word.
- It has to run in `gc_read_stdin`, in the script-body path, and before pre-commit's nocasematch fast exit (`pre-commit-test.sh:498`).
- **It cannot be made fail-closed by construction.** The decoder runs in the hook's bash, but the command runs in the Bash tool's shell, which may be zsh or a different bash. `\u` and `\c` differ between them; in bash 3.2, `$'c'` is literally `c`. A decoder that disagrees with the executing shell in either direction is a silent gap.
- False positives: 0 in principle.
- No parser-matrix impact, since it is pure bash. **Rejected:** most code, and the risk sits in exactly the cases it exists to handle.

**C. (recommended) Any real `$'...'` or `$"..."` word is cannot-determine and is refused.** Implemented as a prototype in a scratch copy of `hooks/lib/git-cmd.sh` and measured (rightmost column of the verdict table):
- `gc_dollar_quote` is a quote-aware awk scan. It skips `'...'`, skips `"..."` except inside `$(`/backticks, and skips backslash-escaped characters. It reports any `$` followed by a quote.
- It is called once at the end of `gc_read_stdin`, so all three gates refuse before any fast exit. The pre-commit fast exit at `:498` would otherwise skip `git $'\x63ommit'`.
- It is called again per script body in `gc_dir_rule`. There it refuses only if the body also has a git or `gh` word, because scripts use `$'\n'` routinely (49 of the repo's own `.sh` lines do).
- **Size:** 35 added lines, 28 of them code.
- **Verdicts:** it closes every `$'`/`$"` row (2, 4, 6–10, 12–16, 18–20, 22, 29, 31, 32), in all three gates on both fixtures. Rows 3, 5, 21, 23 and 28 now block for the right reason.
- **False positives:** 1 of 6,105 agent-shaped commands (0 in the fixtures, 0 in transcripts). Probe rows 35 and 37 are false positives by design. The refusal message names the remedy: plain quotes, with `printf` for escapes.
- **bash 3.2:** uses only `case`, `printf` and awk. No `[[ =~ ]]` and no arrays beyond what already exists.
- **awk portability:** the 37-row probe gave identical verdicts under mawk 1.3.4 and BWK awk 20231127.
- **Parser matrix:** no node, python or jq code, so it adds no parser-dependent rows. Like any change to `git-cmd.sh`, it should get one matrix run before release.
- **Residuals (documented):**
  - A body that encodes the git word itself, such as `$'\x67it' commit` *inside a script*, passes the body check. The typed command is fully covered.
  - Backticks inside `"..."` are scanned with only crude closing. This errs closed (more refusals), never open.
- **Fallback if false positives bite in practice: rule R.** R refuses only when the command also has a git/gh/runner word, or when the `$'` sits in command position. That gives 0 agent-shaped false positives, at the cost of about 10 more lines for command-position tracking. It reopens `env $'\x67it' commit`-style wrapper spellings, an open-ended list, so it is not fully fail-closed. Not recommended as the default.

**Recommendation: C.** It is the smallest of the three, the only one that is fail-closed independent of which shell runs the command, and it has 1 false positive in 6,105 realistic agent commands. Add test rows 2–37 from the table above to `test-hooks.sh`, since the corpus has no `$'` coverage today. Track rows 25 and 30 (backslash inside a word) as a separate item.

---

## Q2: macOS / BSD static audit of `hooks/*.sh` and `hooks/lib/*.sh`

How each finding was checked:

- **"Emulated"** means the gate verdict was **measured** on Linux with a PATH shim. The shim reproduces the documented BSD sed behaviour for exactly the hooks' spellings: `\n` in an `s///` replacement becomes a literal `n`, `\|` in a BRE is a literal `|`, and `\xHH` is not an escape.
- **"Probe"** gives the one-liner to run on a real Mac to confirm the BSD behaviour itself. Expected results: GNU prints `2` and macOS prints `1` (`printf 'a&&b\n' | sed 's/&&/\n/g' | wc -l`); `printf 'ab\n' | sed 's/a\|b/X/g'` gives GNU `XX`, BSD `ab`; `printf '\357\273\277x\n' | LC_ALL=C sed '1s/^\xEF\xBB\xBF//' | od -c | head -1` shows the BOM still present on BSD.

Sorted with fail-open first.

| # | file:line | construct | what differs on macOS | direction | evidence | simplest portable fix |
|---|---|---|---|---|---|---|
| 1 | `hooks/lib/git-cmd.sh:492` (`gc_segments`), `:515` (`gc_seg_quoted`), `:533` (`gc_seg_raw`), `:757` (`gc_text_has_gated`) | `sed 's/&&/\n/g'` | BSD sed writes a literal `n` for `\n` in the replacement, so `a && b` becomes **one** segment `a n b` and `true&&git` becomes `truengit`. The CHANGELOG's T3-7 note ("leaves `&&` chains unsplit") understates it: the segments are glued, not left unsplit. **This is the "macOS gap in splitting chained commands".** | **FAIL-OPEN** | **Emulated, measured.** All 3 gates allow `git checkout feature/x && git push origin main`, `git checkout main && git push`, `git switch main && git push` and `true&&git push origin main`. Pre-commit skips the Test on `true&&git commit -m x`. gate-before-merge allows `echo hi && gh pr merge 5`, `true&&gh pr merge 5`, `git checkout main && git merge feature/x`, `git status && git push origin main` and `echo hi && git push origin main`. Still blocked: `git add -A && git commit -m x`, `echo hi && git commit -m x`, `git add . && git commit -m x && git push origin main`, and every `;` chain. The BSD behaviour is long documented; confirm with the probe. | One helper used at all four sites, so the index alignment between `gc_segments`, `gc_seg_quoted` and `gc_seg_raw` holds: `gc_split_ops() { tr '|;' '\n\n' \| awk '{gsub(/&&/,"\n")}1'; }`. Verified identical on mawk and BWK awk. Alternative: POSIX sed with a backslash plus a literal newline in the replacement. |
| 2 | `hooks/lib/git-cmd.sh:604` (`gc_ps_script_bodies`) | `LC_ALL=C sed '1s/^\xEF\xBB\xBF//'` | BSD sed has no `\xHH` escape, so the BOM stays on the first line of a `.ps1` body and its first command word is not recognised. | **FAIL-OPEN** (narrow: needs `pwsh` on the Mac **and** the gated verb on line 1 of a BOM-prefixed `.ps1`) | **Emulated, measured.** `pwsh ./b.ps1` and `pwsh -File b.ps1` go from BLOCK to allow in no-push-main and gate-before-merge, on both fixtures. Confirm with the probe. | `LC_ALL=C sed "1s/^$GC_BOM//"`, reusing `GC_BOM` from `:321`, which is built with portable `printf` octal. |
| 3 | `hooks/gate-before-merge.sh:202` (`a6_args`) | BRE `\([[:space:]]\|\$\)` | `\|` alternation is a GNU BRE extension. macOS sed's BRE treats it as a literal `\|` unless the regex library's enhanced mode applies. **Needs a probe.** | closed (false positive) | **Emulated, measured.** `git pull --ff-only origin main` on protected `main` goes from allow to BLOCK, so the documented safe catch-up form is refused. | `sed -nE "s/.*[[:space:]]$2([[:space:]]\|\$)/\1/p"` |
| 4 | `hooks/no-push-main.sh:130` | BRE `\(checkout\|switch\)\([[:space:]]\|$\)` | Same GNU `\|`. On BSD `mvargs` comes out empty, the target is unresolvable (`moved=2`), and the hook takes its refuse path. | closed (no verdict change observed) | **Emulated, measured.** No row changed across 5 checkout/switch probes, so this is latent. **Needs a probe.** | `sed -nE 's/.*[[:space:]](checkout\|switch)([[:space:]]\|$)/\2/p'` |
| 5 | `hooks/run-gate.sh:369` | `sed -E 's/[[:space:]]*&&[[:space:]]*/\n/g'` (**Gate extra** leg split) | Same `\n` problem. `bash scripts/a.sh && bash scripts/b.sh` becomes one leg, `bash scripts/a.shnbash scripts/b.sh` (emulation output). The allow-list accepts it, `bash -c` fails with rc 127, and the gate goes red. | closed (gate always fails when **Gate extra** is set) | **Emulated** for the split string; the rc 127 outcome is reasoned from `:652-660` and was not run. | Same `awk gsub` or literal-newline form as #1. |
| 6 | `hooks/gate-before-merge.sh:889` | `grep -qE '\bgh[[:space:]]+pr[[:space:]]+merge\b'` | `\b` in ERE is an extension. macOS grep supports it in practice, but that is not guaranteed. | none observed | **Emulated worst case** (`\b` read as a literal `b`): no verdict changed. The other `gh pr merge` recognisers cover it. | `(^|[^[:alnum:]_-])gh[[:space:]]+pr[[:space:]]+merge([^[:alnum:]_-]|$)`, the same form as `no-push-main.sh:71`. Optional. |
| 7 | `hooks/lib/git-cmd.sh:604`, `:688` (`head -c 16384` feeding `grep`/`sed`/`tr`) | byte-count truncation | macOS `tr`/`sed`/`grep` in a UTF-8 locale can fail with "illegal byte sequence" when a multibyte character is cut at byte 16384. The body text could then be dropped. | possibly OPEN; **needs a probe** (a body over 16 KB with non-ASCII at the cut) | Static only. This is an edge of the already-documented 16 KB cap. | Run the body pipeline under `LC_ALL=C`. |
| 8 | all `awk` programs (`GC_AWK_IS_GIT`, `gc_push_args`, `gc_matches_subcommand`, `a6_strip_redir`, `json.sh:405`) | `-v bs='\'`, `tolower`, `index`, `-v BINMODE=3` | macOS awk is BWK (Sonoma ships 20200816). | none observed | **Measured** with BWK awk 20231127 as `awk`: 58 probe commands gave identical verdicts to mawk, and `-v bs='\'` yields a 1-character backslash in both. A minor version gap to macOS remains. | none |
| 9 | bash 3.2 (`/bin/bash` on macOS) | `[[ =~ ]]` / `BASH_REMATCH` (`git-cmd.sh:572,583,798,826`), `local -a`, `+=`, `shopt nocasematch` (`pre-commit-test.sh:498`, bash 3.1+), `${x:0:1}` | None found. There is no `declare -A`, `mapfile`, `${x,,}`, `&>>`, `\|&`, `;&`, `local -n`, negative indices or `{fd}>`. Regexes are passed through variables, which is the bash 3.2-safe form. | none | **Static only.** bash 3.2 source could not be fetched (the proxy denied ftp.gnu.org and github.com). | none. Worth one CI or Mac run of `test-hooks.sh` under `/bin/bash`. |
| 10 | `stat -c %Y` (`gate-before-merge.sh:1506`, `run-gate.sh:565`, `json.sh:332`), `sha256sum` (`git-cmd.sh:1248`, `run-gate.sh:156`), `mktemp` with no template (`pre-commit-test.sh:901,971`, `run-gate.sh:484`), `find -maxdepth -mmin -delete`, `head -c`, `ps -A -o pgid=`, `date +%s`, padded `wc -l` (`gate-before-merge.sh:1468,1492`) | GNU spellings | Each already has a BSD fallback (`stat -f %m`, `shasum -a 256`, the `\|\| echo` paths), or is supported by macOS/BSD (`find`, `head -c`, `mktemp` on 10.11+, `ps`). `[ 1 -le "   3" ]` tolerates `wc`'s padding (measured). | none | Documentation, plus local checks where noted. | none |

**Fail-open count: 2 confirmed by emulation (#1, #2), plus 1 that needs a probe (#7).** The worst is **#1**: on a Mac, `git checkout feature/x && git push origin main` passes all three gates, and `true&&git commit` skips the Test. One small helper closes it. It is the T3-7 backlog item, now with measured rows. Before shipping the fix, confirm on a real Mac with `printf 'a&&b\n' | sed 's/&&/\n/g' | wc -l`.
