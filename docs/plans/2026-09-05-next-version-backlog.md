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
