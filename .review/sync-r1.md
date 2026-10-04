# Sync fix round 1 + Task 7 (S4): controller log

Branch `feat/v4.3.1-sync`, base `de5388a`. Implementers ran on sonnet and reviewers on opus. Scratch file: delete after reading.

## Item A: S8-1 / S8-2 fix round

- `19493ac` fix(v4.3.1): sync review round 1 -- skill never defaults to overwriting an untracked hook; small server fixes (S8-1, S8-2)
  - TDD RED, before the server change (11 failed = the 9 known + 2 new):
    - `test_template_sync_strict_params.py::test_template_verify_rejects_an_unknown_mode_value`: no `ok` key.
    - `test_template_sync_v3_finalize.py::test_finalize_v2_path_counts_files_created_separately`: no `pending_once_notes`.
  - GREEN: 9 failed (the known Windows-path tests) / 486 passed / 1 skipped.
- `c4210e9` fix(v4.3.1): sync review round 1 follow-up -- rules list and keep-mine wording match step 6b (S8-1)

### Review 1 (19493ac): Spec FAIL · Quality CHANGES REQUESTED

- Important 1: SKILL.md:1363. The NEVER-rules list still said "differing accepts the template with source=template", which restores the #173 default. **Fixed in c4210e9.**
- Important 2: SKILL.md:865. "Keep mine = RENAME, then apply" contradicted the new register-only keep mine at :861. **Fixed in c4210e9:** it is now an optional extra choice the user picks explicitly.
- Minor 3: SKILL.md:602. "template-class has no keep-mine" needed a tracked-file scope. **Fixed in c4210e9.**
- Minor 4: SKILL.md:1012. "register-or-apply route" wording. Harmless; left as is.
- Passed: S8-2 items all done; refusal quote matches v3.py:1434-1436; S8-3 untouched; LF; test-server 9F/486P/1S.

### Review 2 (c4210e9): Spec PASS · Quality APPROVED

- Critical / Important: none. A whole-file grep found no silent-overwrite path left for a present untracked hook.
- Minor (open, optional): SKILL.md:865. The rename choice says "apply as the adopt-template bullet above", which passes `overwrite_existing=true` on a file that is by then absent. Harmless, because absent files are unaffected. Could say "as in sub-step 3".

Pushed `de5388a..c4210e9`.

## Item B: Task 7 (S4) skill wording

- `f9f9206` docs(skill): sync-template wording from the five consumer reports (S4)
  - Steps 1-6 and 8 are verbatim.
  - Step 7 (the tree-named artifact) is SKIPPED because it depends on Task 4.
  - Ruling S-9 is one sentence at SKILL.md:1031 (`applied_files_path`).

### Review (f9f9206): Spec PASS · Quality APPROVED

- Critical / Important: none.
- The plan's backtick spans were checked character by character, and all of them are present.
- Step 5 sits after the "So: delete the LOCAL branch" paragraph, so the quoted refusal stays with its explanation. The reviewer judged this acceptable.
- No `last-pass.tree` text; check 47 clean; 0 CR; consistency ALL CHECKS PASSED.
- Open Minor findings (need a ruling):
  1. SKILL.md:1019. The step 7 call line still reads `applied_files=<JSON array ...>`. Changing it to `applied_files_path=<json-path>` would close the hand-typing path completely. S-9 allowed only one sentence, so this was left alone.
  2. SKILL.md:467-469. This comes from the plan: `<repo>` means both the directory name (file names) and the full path (`"cwd":"<repo>"`). The cwd assertion at :498 fails loudly, so the cost is low.

## Tallies

- test-server (after Item A): 9 failed / 486 passed / 1 skipped. The 9 failures are the known Windows-path tests (3 in test_load_fields.py, 6 in test_template_sync_msys_guard.py). Item B changed SKILL.md only.
- SKILL.md bytes:
  - 230108 at `de5388a`
  - 230783 at `19493ac`
  - 231101 at `c4210e9`
  - 234014 at `f9f9206`
