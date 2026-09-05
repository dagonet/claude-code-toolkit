# Next-version backlog — feedback from the v3.0.3 verification and sync round

Gathered 2026-09-04/05 from the five consumer sessions (open-brain, panoscribe, yutraffic, penumbra, MM-Agent) that verified `cfef02e` before the tag and synced to v3.0.3 (`86561fe`) after it. Each item carries its source and its **reason**, so nothing is dropped later as a duplicate or a nit. **Measured** means a consumer reproduced it; **derived** means it was read from source but not exercised.

Recommended split: a small **v3.0.4** patch for the cheap items consumers hit in their first sync, then **v3.1** (ownership model, template diet, gate-checked branches — specs on PR #83). Items marked *v3.1* are either subsumed by the v3.1 sync redesign or need a design pass that belongs there.

## v3.0.4 — cheap, consumer-hit-in-first-sync

### Suite rows (permanent regression coverage the release measured but did not encode)
- **`; true` want-artifact row — the OVER-CORRECTION CONTROL.** The only row that goes RED if the `**Gate**:` read is later tightened into refusing honest Gate values; the deceptive and garbage rows get *greener* as the parser tightens and cannot detect that. (open-brain, measured on cfef02e: `bash real-gate.sh ; true` → marker T, artifact T, intended.) Do not drop as a duplicate of the deceptive row.
- HTML-comment shape `- **Gate**: false  <!-- **Gate**: true -->` and open-brain's remaining marker rows (trailing `**Field**:` text, bare-bash truncation, double-star mid value). Pre-fix the HTML row failed only by accident (unbalanced quote), so it is regression coverage, not proof the old code was safe. (open-brain, panoscribe, measured.)
- `pre-commit-test.sh:307` `GATE_CMD_RAW` extractor is **derived**, not measured — needs a path that prints the extracted value. (panoscribe.)

### Text and docs
- `deny-secret-reads.sh` DENY text: add *"this matched the command TEXT; a literal secrets filename in any argument is enough."* Two consumers were blocked within minutes by `grep -c 'Read(\.env' settings.json` — the obvious post-sync check trips the hook that replaced the rules. Over-block is right; the text should say why. (yutraffic, open-brain, measured.)
- Migration note: *verifying the retirement trips its replacement — put that check in a script file, where the hook sees only `bash <path>`.* (open-brain.)
- PROJECT_CONTEXT `**Gate**:` field comment: *join steps with `&&`, never `;` — `;` discards an earlier failure status and the gate mints a pass on a failing suite.* Shell semantics, pre-existing, independent of the truncation fix; no shipped template uses `;` (checked at cfef02e). (panoscribe, measured.)
- Artifact docs: `run-gate.sh:177-178` hashes the tree via `git add -A` into a temp index, so **any untracked file changes the artifact `tree`** — tree-freshness (the arm that carries rebase/amend-preserving-content) is defeated by a stray build file or swap file → spurious "artifact stale" after a sha change. Doc line now; `git add -u`/tracked-only is a *v3.1* design pass because it changes what the gate hashes. (panoscribe, measured.)

### Sync skill (`user-level-reference/skills/sync-template/SKILL.md`) — carries into v3.1 unchanged
- **Step 2b control is defeated by a `.gitignore` with no trailing newline** and fails in the *reassuring* direction: `printf '%s\n' >> .gitignore` concatenates the planted path onto the last real rule, the control reports "planted path not ignored" (reads as a broken derivation), and a real rule is silently corrupted for the check's duration. Fix: append with a LEADING newline and assert the last pre-existing rule is unchanged after restore. (panoscribe, measured.)
- **Step 4: misplacement is a second failure mode with the same clean signature as dropped lines.** A `has_conflicts:false, dropped_lines:[]` merge put the new Gate/Test comment ~30 lines from the `**Gate**:` line it annotates; every step-4 check passed. "A clean merge is not a correct merge" must define correctness as placement AND presence. Skill wording now; the three-way-merge behaviour is a *server* item (mcp-dev-servers). (yutraffic, measured.)
- **Step 6b: a file applied THIS sync reads PRESENT-BUT-UNTRACKED** against the on-disk manifest until finalize writes it → false "needs `source=skip`". Clause: compare against the manifest **plus this sync's applied set**. (yutraffic, measured.)
- Generalise the `/tmp`-is-invisible-to-Windows-`python3` warning beyond step 2b to any bash→python handoff (a 6b helper died on `/tmp/ref.txt`). (panoscribe, measured.)
- Step 7b may be redundant: `template_finalize_sync` appears to write `lastSyncedVersion` in the correct header position itself. Verify; if so, shrink the client-written section. (open-brain, observed.)

### Consistency script
- Check 21 walks from the MIRROR (`user-level-reference/hooks`), so a root hook that was never mirrored is invisible to it; 21b covers `json.sh` only. Make the walk bidirectional (root `hooks/**` must have a mirror or be on an explicit no-mirror list). (open-brain, read at source.)

## v3.1 — subsumed by the redesign or needing a design pass
- Sync three-way merge: placement-aware correctness (see step 4 above) — the merge is being redesigned with the ownership model; carry the requirement, not a patch.
- `lastSyncedVersion` ownership (server-written) — settle in manifest v3.
- `run-gate.sh` tree hashing: tracked-only (`git add -u`) vs `add -A` — changes what the gate hashes; design pass.
- Finding 59 provenance channel: export `RUN_GATE_TERMINAL` across the Test `eval` so a Test command can claim the terminal contract; clamp on `rc==78 && marker present`.
- Merge-gate `-c` classifier sits inside the protected-branch condition (gate-before-merge ~:844) while no-push-main's precedes resolution — a documented per-hook asymmetry, not a widening; revisit only if the gates are unified.
- Profiling: `gate-before-merge` ~+700 ms and `no-push-main` ~+350 ms vs v3.0.2 (paired interleaved, rotated, R=31, p<0.001; magnitudes approximate). Direction generalises, magnitude does not.

## Added after the v3.0.4 round (2026-09-05)

Gathered from the v3.0.4 verification round: yutraffic, open-brain, panoscribe, penumbra, MM-Agent. Sources are named per item; where a v3.0.4 item is only referenced (not restated), see `docs/plans/2026-09-05-v3.0.4-plan.md` on `main` for its text.

### Closed in v3.0.4
- MM-Agent's untagged-HEAD sync item — shipped as SKILL.md §1b (pre-step recording the tag commit when the tracked tree is identical to it).
- penumbra items 5 and 6 (see `penumbra-v303-feedback.txt`) — shipped as SKILL.md §1b and the fourth presync trap, respectively.
- The v3.0.4 items themselves, by label — see `docs/plans/2026-09-05-v3.0.4-plan.md` on `main`.

### New v3.1 items

#### git-cmd.sh:937 — the `-C` fallback classifies any argv word equal to the verb as the verb (penumbra); merged with the Class-3 `-C` scope note (penumbra, yutraffic)
`gc_matches_subcommand` arm 1 anchors the verb (`${GC_GIT_PRE}[[:space:]]+$2([[:space:]]|$)`); when it fails and the segment carries `git -C`, the fallback at line 937 is `\bgit\b.*\b$2\b` — unanchored, word-bounded, over the whole remainder. `-` is a word boundary, so `merge-base`, `merge-tree`, `merge-file` match "merge"; any token equal to the verb (`--grep=merge`, a path `docs/merge.md`, a branch `feature/push-fix`) matches too. Measured from a protected branch, literal paths, all read-only: `cd <toolkit> && git merge-base A B` → 0; `git -C <toolkit> merge-base A B` → 2 "a merge on a protected branch", A6_KIND=merge; `git -C <toolkit> log -1 --grep=merge` → 2 same; `git -C <toolkit> log -1 --grep=push` → 2 via the push arm. Over-refusal only (arm 1 is exact, no under-match) but the discriminator names a merge rule for a command with no merge in it. Fix: after `-C <operand>` and globals, match the verb as the first non-option token with arm 1's anchor, or fold `-C` into GC_GIT_PRE. Fixture: the four rows above plus a want-2 control `git -C <path> merge feature` on a protected branch.

This is also the resolver's still-top item: **Class-3 `-C` refusal fires before verb classification.** `git -C $T merge-base A B` is refused twice — class 3 first (unresolvable `$T`, before the verb is known), line 937 second (once the path is literal) — both must go, or the B1 §1b instruction (`-C <templateRepo>` + descendant reasoning) fails on its first line. Penumbra's original report: `git -C $T merge-base A B` refused as unexpanded `-C` operand even though `merge-base` is read-only plumbing; workaround was a literal path, at the cost of every read-only probe in a fixture script needing one. Resolve the subcommand first and refuse an unresolvable `-C` only when the verb is one the hook gates, or at least let plumbing (`merge-base`, `rev-parse`, `log`, `status`, `diff`) through with an unresolved `-C`. Parser-matrix rows.

#### setup-project.ps1:861 — unguarded `git rev-parse` under `$ErrorActionPreference = "Stop"` on a no-`.git` checkout (open-brain)
`:80` sets Stop; `:861` runs `& git -C $PSScriptRoot rev-parse --short HEAD 2>$null` unguarded (the script guards the same trap at `:153-175` for target detection); the manifest write (~`:905-921`) and `Write-AutoModeSnippet` (`:958`) come after it. On a toolkit extracted without `.git` (ZIP download) PS 5.1 turns the stderr into a terminating error and the script exits 1. Paired control on the same tree: `setup-project.sh` exit 0, 31 files, manifest written; `setup-project.ps1` exit 1, 30 files, `.claude/template-manifest.json` ABSENT. The aborted run looks like a successful bootstrap; the missing manifest is invisible until the first `/sync-template`, which lands the user in step 2b's adoption worst case. Four parts: (1) guard `:861` like `:153-175`; (2) check 27's ps1 arm asserts the exit code, not only the snippet count; (3) SKILL.md 2b's "on Windows as well as POSIX" claim made true (v3.0.4 qualified it); (4) fixture asserts `.claude/template-manifest.json` exists after a ps1 bootstrap. open-brain's paired-control fixture is the regression test and they will run it against the fix.

#### `.gate/last-precommit.json` is overwritten by every Bash call (MM-Agent)
Each non-commit Bash call writes `path=no-commit-segment, rc -1, elapsed ~1-2 s`, so the row written by a commit's own hook survives only until the next Bash call, and a consumer reading it through Bash always reads its own read command's row. Step 9 item 5 cannot be satisfied from inside a session. MM-Agent proved the gate ran by external evidence (message-file mtime → three dotnet workload logs → commit date, ~620 s). Fix: write the artifact only when a commit segment was found, or write non-commit notes to a separate file, or keep the last N rows. Related: a Bash command that contained `git commit -F …` only inside a single-quoted printf argument ran the full Test line (615 s) — correct fail-closed, but the artifact should carry a `matched-inside-quoted-word` note so the consumer can see why.

#### Commit gate is keyed to the payload cwd, not an in-command `cd` (controller, measured)
`cd <worktree> && … && git commit -F …` was gated against the session cwd at call time (the main checkout): Test ran there (path=test, 100 s, rc 0) and the artifact landed in the main checkout's `.gate/`. Harmless when both trees match; a `cd` into a different repo would test the wrong one. Document, and consider refusing a commit segment preceded by a `cd` clause (same shape as the mover-clause rule).

#### Identity-transfer rule (yutraffic, panoscribe) → `docs/verification.md`
A verdict names a sha. It transfers to a new sha only when (a) the new sha is a descendant (equal hashes on a rebuilt non-descendant tree do not transfer) and (b) every path the verdict rests on is byte-identical — hook-hash identity carries hooks; it does not carry SKILL.md or `scripts/test-hooks.sh`, which are executed procedure and must be re-read. A transfer claim must say which items transferred by hash and which were re-checked. "Docs-only" is a description of intent until the diff confirms it.

#### VERSION line 2 (controller)
VERSION holds two lines: semver, then that release's one-paragraph summary (since ≤ v2.3.0, undocumented). v3.0.4's squash left line 2 describing v3.0.3 (fixed in the follow-up tagged as v3.0.4). Add a consistency check that line 2 differs from the previous tag's line 2, and document the convention.

#### deletedAcknowledged — consumed by the server or only by the skill? (MM-Agent → server owner)
After stamping `deletedAcknowledged: [requirements-engineer.md, test-writer.md]`, `template_compute_status` still reports `template_deleted 2` and lists both. Question for the mcp-dev-servers owner: if consumed server-side, it suppressed nothing visible.

#### Server: retry the final rename with backoff and clean its own `.tmp` (MM-Agent)
`template_apply_file` on `hooks/gate-before-merge.sh` failed three times with `WinError 5` while a live run held the broad-matcher hook open; each failure left a `.tmp` beside the target. Skill text ships in v3.0.4 (§ live-run rule); the server-side retry + cleanup is the v3.1 half.

#### Probing the project copy of deny-secret-reads needs a script file when the user-level hook is installed (MM-Agent)
An inline probe naming `.env` is blocked by the user-level hook before the project copy is reached; the probe must live in a script file (`dsr-probe.sh`). Skill warning for step 6b. (This is a probe of the hook, not a bypass recipe for it — say so in the text.)

#### Keep-mine splice anchors differ per project (MM-Agent)
PROJECT_CONTEXT.md's implied Edit anchor (the `## Paths` neighbour) did not exist; re-anchored on the Mixed-target caveat paragraph. Skill: name the anchor as a heading search with a fallback, not a fixed neighbour.

### penumbra's v3.0.3 items (verbatim mechanism, from `penumbra-v303-feedback.txt`)

#### 2. Pipe-refusal wording blames the wrong clause (penumbra)
`git push origin br 2>&1 | tail -1` was refused as a mover. Refusing the whole call is arguably correct (`2>&1 | tail` is non-inert on the gated verb), but the discriminator message called `tail` an "earlier clause" when it is the pipe's *later* one — a wording bug that makes the refusal look wrong when it is right. Also: a compound `git checkout -b X; git add ...; git commit ...; git push ... 2>&1 | tail -1` was refused whole and evaluated from main (checkout never ran) — correct, but the message did not say "evaluated from current branch main because checkout is in the same call." One sentence would save the next consumer the reasoning.

#### 3. `template_get_diff` diff_type mismatch (penumbra, for the mcp-dev-servers owner)
`template_get_diff` rejects `diff_type "unified"` while its response carries a `unified_diff` field. Penumbra used `three_way` instead. Either accept `"unified"` or drop the field-name mismatch.

#### 4. `region_preserved:false` on a placeholder-only PROJECT-CUSTOM region reads as alarming when benign (penumbra)
Seen on `tester.md` and `AGENT_TEAM.md`. A `region_empty` or `region_placeholder_only` distinction would say which case applies.

#### 7. Step 8 report wants a "Sync server:" version with nowhere to source it (penumbra)
Nothing in the workflow surfaces the sync server's version after step 1's version check, so penumbra reported "unknown." Have `template_load_manifest` echo `server_version` into the report template.

#### 8. Prediction-committed-first rule needs a branch-provenance clause (penumbra)
The prediction-committed-first rule in the pre-sync section is good; add "the prediction commit must be made from a branch whose commit-minted artifact matches, or the sync branch's first commit fails the merge gate" — penumbra hit this earlier in the cycle via an in-repo message file and an untracked review file (`add -A` hashes them).

## Untested classes (owed by a consumer on another platform, not by the toolkit)
- `*` and `?` glob operands in `-C` paths — NTFS forbids them in filenames, so every Windows measurement covers bracket forms only. A Linux consumer owes those arms.
- Symlinked `-C` targets, UNC paths, NTFS case-insensitivity (`/TGT` vs `/tgt`), `GIT_DIR`/`GIT_WORK_TREE` overrides.
- Known safe-direction limitation: the segment splitter strips quotes, so `'~/path'` classifies like `~/path` — an over-block, not a bypass.

## Confirmed fixed by the sync round (no action)
- The v3.0.0 resolution-label bug: `source="provided"` now yields `resolution_at_sync: ""`, not spurious `keep-mine`. (yutraffic.)
- Retirement order: the sync retires the six `Read(.env*)` rules AND lands `deny-secret-reads.sh` together; removing the rules first leaves a window with neither. (open-brain; panoscribe measured the hook denying *before* removing the rules — the recommended order.)
- Guards firing on their own authors in the field: the checkout-then-pull ordering rule (newlines are not separate calls), `enforce-delegation.sh` on an investigation grep, and the SPLICE-never-accept warning (`{{GATE_COMMAND}}` would have silently disabled a consumer's gate). A guard nobody sees fire looks like one that was deleted; these were seen. (panoscribe.)

## Verification rules that came out of the round (already in `docs/verification.md`, listed for the record)
1. Re-run every row that used a control later found invalid — an invalidated control voids past results retroactively.
2. Probes are script files, never inline; `GIT_PAGER=cat`, `--no-pager`, a hard timeout.
3. Fixture repos must be distinguishable (marker or distinct exit codes) and asserted through git; identical fixtures cannot tell "resolved to the right one" from "resolved to any one".
4. A check that shares the fixture's failure mode proves nothing in either direction.
5. Run the harness against a known-answer state before the candidate; pin known defects as a positive control — a detector must go red before its green means anything.
6. A 127 is a non-measurement that voids the run (production signature of an absent hook failing open); re-verify hashes at the END of a run, not only the start.
7. The fixture must make the correct answer reachable only through the path under test — protected-on-main, refspec-naming-main, always-fail Test, identical Tests were the four masks.
8. A control that holds on only one of two compared baselines is not a control.
9. Fixture briefs say WHERE to write, paths built from the workdir variable; `git status` the real repo after any fixture-heavy run; never extract the subject into a path the harness cleans.
