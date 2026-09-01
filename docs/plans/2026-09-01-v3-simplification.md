# Simplification — three releases: v2.2.6, v2.3.0, v3.0

**Owner decision (2026-09-01):** *small enough that mistakes are visible; fewer moving parts; more trust in the operator.* KISS. Remove unused machinery, provide local extension points, and **migration documentation must be thorough and waterproof** — five consumer repos migrate (open-brain, penumbra, Yutraffic-Challenge, panoscribe, Motorsport-Manager-AI-Agent).

**Baseline:** `main` = `30e7554` (v2.2.5 + PR #73). **Gate:** `bash hooks/run-gate.sh`.

> **This plan is the post-challenge version.** The first draft was rejected on four counts by an architect review; the corrections are load-bearing and are recorded in §6 so nobody re-imports the original reasoning.

---

## 1. What the evidence actually says

Measured over **820 transcripts, 1.16 GB, 2026-08-02 → 2026-09-01, 7 repos**. Report: `.superpowers/sdd/simplify/usage-measurement.md`.

**The critical split — the report measures a FLEET, not this codebase:**

| | blocks | traps | wasted turns |
|---|---:|---:|---:|
| `block-bash-vcs.sh` — **already deleted** | 399 | 35 | 74 |
| inline agent-frontmatter `git`/`gh` — **already removed from templates** | 225 | 200 | 110 |
| **subtotal — NOT SHIPPED** | **624** | **235** | **184** |
| `pre-commit-test` + `gate-before-merge` + `enforce-delegation` + `no-push-main` — **shipped** | 242 | **31** | 56 |

Reconciles to the report: 235 + 31 = 266 ✓; 184 + 56 = 240 ✓.

**The guard surface we can change produced 31 traps in 30 days across 7 repos — roughly 19 wasted turns a month excluding `pre-commit-test`'s correct blocks.** There is no trap crisis in shipped code. Any plan claiming otherwise is measuring removed machinery.

The three repos still carrying the 98%-trap inline hooks (OmniScribe, KnowledgeGame, WebSiteVerifier) are **not** among the five migrating consumers. That cost is real but is **not addressable by any toolkit change** — it is a one-line advisory to three repos.

### Surface

```
hooks/*.sh + lib            14 files    2,517 LOC
verify-template-consistency.sh          1,616 LOC
test-hooks.sh                           2,336 LOC
templates/general/AGENT_TEAM.md         1,026 LOC  x6 = 6,156 shipped
sync-template/SKILL.md                    633 LOC
templates/general/CLAUDE.md               157 LOC
agent files                                68
```

### Measurement caveats that constrain conclusions

- **Main-thread hook stderr never reaches transcripts** → main-thread blocks are systematically **under**-counted.
- `rust-coder` / `java-coder` zero-use is an artefact: **no rust or java repo is in the corpus.**
- `block-bash-vcs`'s 1,240-turn figure is neither confirmed nor refuted; the window sees only its tail.
- **Never infer DELETE from silence.** An invisible mechanism's count is *unknown*, not zero.

---

## 2. Release 1 — v2.2.6 (patch, no subtractions)

**Purpose: clear the verification tooling that every later migration depends on, and give consumers one more clean sync at the current shape.** Folding twelve behaviour fixes into a subtraction release makes the first field failure undiagnosable.

1. **Fix 6b's hook-reference extractor.** It anchors on the `command:` value; the path sits after an escaped quote, so it recovers **zero** from `settings.json` and printed `5 referenced, 5 present` while seven hooks went unchecked. **This is the only check a consumer runs to confirm their hooks are wired — a subtraction release cannot be verified by a collector known to under-count hook references.** Fix: `grep -o 'hooks/[A-Za-z0-9_.-]*\.sh'`, the step's own over-collection principle.
2. **Wire the toolkit's own gates.** `pre-commit-test.sh` and `gate-before-merge.sh` are registered **nowhere** for this repo — measured: `git commit` completes in **0 s** against a 58–117 s `**Test**`. Ship a project `.claude/settings.json`. Without this, "gate green at every phase boundary" is an operator claim, not an enforced property, in the releases that remove enforcement.
3. **The remaining queued items** in `.superpowers/sdd/sync-feedback/progress.md` — 7b fixture trap (three independent reports), 7b stamping order, manifest key order, the `lastSyncedVersionOf` docs row, step 2b's wrong worst case, piping the gate, short-vs-long field names, annotated-tag deref, the VERBATIM INSTALL abstention.

**Migration:** ordinary sync. Nothing removed.

---

## 3. Release 2 — v2.3.0 (extension points)

**The whole benefit of the simplification programme lands here, and it lands across the fleet.**

### ⛔ `hooks/local/` IS CANCELLED — the contract already exists and is already exported

**The premise was never measured.** I claimed *"two repos maintain merge scripts reassembling `run-gate.sh`"*. Measured by the consumers themselves: **one repo, one file, one 13-line insertion, zero other edits.** The other has **no splice at all** — every `hooks/` file template-tracked and byte-identical to the tag. An extension point would be a **permanent surface for a single deviation.**

**A `**Gate**` chain already works today** — `**Gate**: bash preflight.sh && <real gate>` — with one catch the consumer found before I could ship the mistake: inside `run-gate.sh` a spliced preflight exits as the **script's own** exit, upstream of the clamp, so its 78 survives. **Chained into `**Gate**`, the same 78 becomes the gate command's rc and the clamp destroys it** — item K's own defect, reintroduced by the migration meant to retire the splice.

**The marker is exported, and that is the whole answer.** `run-gate.sh:170-171` exports `RUN_GATE_TERMINAL` into the gate command's environment, so a chained preflight can signal terminal legitimately:

```sh
# preflight.sh
if ! <precondition>; then
  echo "GATE ERROR: <what>" >&2
  echo "run: <remedy>"      >&2
  [ -n "${RUN_GATE_TERMINAL:-}" ] && : > "$RUN_GATE_TERMINAL"
  exit 78
fi
```

The clamp passes it through, and the terminal branch is **deliberately silent** so the guard's own remedy stays last on stderr — exactly what a consumer preflight wants.

**So v2.3.0 ships ONE DOCUMENTED SENTENCE instead of a directory:** *if your `**Gate**` command hits a terminal condition, print your remedy, touch `$RUN_GATE_TERMINAL`, and exit `$GC_TERMINAL_RC`.* Zero new toolkit surface, nothing to sync, no manifest interaction — and it hands the terminal path to **every** consumer's Gate command rather than only to splice-holders. **Strictly more capability for strictly less code.**

**Honest cost, flagged by the consumer rather than discovered later:** it promotes `RUN_GATE_TERMINAL` from an internal detail to a **public contract** that can no longer be renamed or repurposed freely. It is *already* exported, so consumers can depend on it today whether or not it is documented — which argues for documenting it deliberately rather than leaving it a discoverable accident.

**Also rejected: siting any extension point inside `hooks/`.** That tree is template-owned and the manifest's model is *the template owns these paths*; a project-owned file there is re-proposed every sync as a keep-mine conflict, **training click-through in step 5, whose failure mode is losing a file with no history.** *A guard that cries wolf every sync is worse than no guard, because it teaches the reflex that defeats it.*

<details><summary>Superseded original item</summary>

1. **`hooks/local/` extension point.** Consumers splice `hooks/run-gate.sh` because we gave them nowhere else; **two repos maintain merge scripts whose only job is reassembling it every release.** `run-gate.sh` sources a local pre-gate when present.
   - **Undeclared dependency, must be resolved first:** the sync server's `hooks/` walk **offers gitignored artifacts** (a deferred upstream minor — *"filter via `git ls-files`"*). Until that lands, `/sync-template` surfaces `hooks/local/pre-gate.sh` as a sync candidate on every consumer sync — in the step whose failure mode is data loss. **Either land the upstream filter first, or site the extension point outside `hooks/` (e.g. `.claude/local/pre-gate.sh`).**
   - **Constrain the contract:** a local pre-gate may only **fail** the gate, never satisfy it, and its absence is silent. Otherwise `.gate/last-pass.json` attests to a different gate than CI ran.
2. **Heredoc-body stripping in `enforce-delegation.sh`** — a fail-open policy hook with 14 heredoc traps, the only heredoc traps in shipped code. Heredoc bodies have an explicit terminator and are safely strippable.
   - **Do NOT touch `git-cmd.sh`.** Its header states the polarity rule explicitly: the three fail-closed gates scan the whole string *on purpose*, so `bash -c "git push origin main"` cannot evade them, and a false positive on `echo "git push origin main"` costs one retry. `enforce-delegation.sh` does not source `git-cmd.sh` — that is the design, not an oversight.
3. **Document `settings.json` matcher extensions.**

**Only one structural edit to `run-gate.sh` in this release.** Two edits in one release is what broke a consumer merge script in v2.2.5 (a comment moved between an `echo` and a `cd`). Land the extension point alone.

**Migration lead:** *you can stop maintaining your merge script.* Quantify honestly — ~19 wasted turns a month across 7 repos. Small, and saying so makes the real benefit credible.

---

## 4. Release 3 — v3.0 (the subtractions)

1. **Shrink `AGENT_TEAM.md` to ~150 lines. Do NOT delete it.**
   - **Keep:** the tier model (46 spawn prompts reference it), the Spawn-Prompt Binding Table (check 10 diffs it against `require-skills-block.sh`), worktree/merge protocol, PROJECT_CONTEXT template.
   - **Cut:** retrospective templates, session-summary templates, communication protocol, permission batching, implementation-plan appendix.
   - **Why not delete — this is a data-loss hazard, not a preference.** Check 25 asserts the file ends with a `PROJECT-CUSTOM` region, and `SKILL.md:264` instructs consumers to move their custom lines **into it**. Deleting the file deletes consumer-authored content the toolkit told them to write there — the item-G class the series shipped a critical fix for, through a different door. Shrinking captures ~85% of the saving with **zero** migration risk: no `TEMPLATE_DELETED`, no PROJECT-CUSTOM loss, no dangling `architect.md` frontmatter (×6 + user-level say *"Read AGENT_TEAM.md"*), no setup-script change; checks 4/5/7/25 keep working. Only checks 8 and 14 need touching.
2. **Agent consolidation — 68 files, working set ~6.** This is the release's **one real deletion**, and it carries the analogue of the 127 hazard: a committed plan or running session spawning a removed `subagent_type` fails at spawn.
   - **Name the survivors explicitly.** "68 → ~6" is not a specification.
   - **Deprecation release for the agent files**, same shape as the hook-stub rule in §6.
   - `require-skills-block.sh`'s case statement enumerates subagent types; consolidation changes it, which changes check 10's diff against the binding table. **Sequence both in one commit or the release fails its own consistency gate.**
   - **Do not cut `rust-coder`/`java-coder` on zero-use** — no such repo is in the corpus.
3. **The DEMOTE actions**, which the first draft named and never scheduled:
   - **`agent-budget-warn.sh` must exempt `SendMessage`.** It blocked **5 agent reports** — it stopped agents filing their work, the exact failure the liveness work exists to prevent. Highest-value concrete fix in the report. Keep the ceiling (spawns hit 420, 480).
   - **`enforce-agent-contract.sh`** — cap re-blocks; one session looped 28×.
   - `require-skills-block.sh`, `read-size-gate.sh` — demote.

---

## 5. Migration — waterproof means these specific things

Every item traces to a measured incident in this series.

1. **RESTART is a numbered step, not a footnote**, placed *before* the step relying on new behaviour. Measured live: a session executed v2.2.4 steps while disk had moved twice, every check green. **A running session obeys the body it LOADED.**
2. **The definition of done is a probe that runs** — `verify-user-level-drift.sh` reports 0 drift **against the released tag** — never "copy the files".
3. **Every consumer merge script will fail, and that is correct.** Say so up front and frame it as intended.
4. **Tell each splice-holder what happens to their splice.** v2.3.0 retires them; that is the selling point.
5. **State what did NOT change.** Four consumers reported their v2.2.5 sync never exercised the critical fix; change-only notes leave a reader unable to tell *unaffected* from *untested*.
6. **A two-sided probe per surviving gate**, runnable in a minute — e.g. `git push --dry-run origin main` expecting a block whose message names the branch set it read (`(main)` vs `(main master)`).
7. **Version by SOURCE version.** Consumers sit on different SHAs; several sync two releases in one pass, so an intermediate release can appear nowhere in their history.
8. **`git rev-parse <tag>` is the tag object** — verifying `lastSynced` needs `^{commit}`.
9. **Rollback, stated per release:** the previous tag, and what re-syncing the older version over the newer tree does to the manifest.

---

## 6. Rejected — recorded so they are not re-imported

- **Deleting a fail-closed hook in a single release.** Registrations are 127-wrapped (`exit 2`), so a deleted script hard-blocks a consumer's repo. If a fail-closed hook is ever deleted it goes through a **no-op stub release first**. **Not applicable to these three releases — none of them deletes a hook**, and shipping the stub apparatus anyway would be this plan's own KISS violation. **Say POLARITY, not "wrapped" — a consumer checking the obvious way reaches the opposite conclusion.** Measured on the shipped `templates/general/.claude/settings.json`: **all nine PreToolUse registrations carry a 127 guard**, so grepping for `127` returns nine of nine and reads as "all fail-closed". **What differs is what the 127 branch DOES:**

```
pre-commit-test / no-push-main / gate-before-merge x2 / require-skills-block
    127 branch -> exit 2    missing script BLOCKS      <- stub release REQUIRED before deletion
read-size-gate / enforce-delegation x2 / agent-budget-warn
    127 branch -> exit 0    missing script WARNS+ALLOWS <- deletable without a stub
```

A consumer measured "nine registrations, nine wrapped" and concluded the deletable set was empty — a reasonable reading of a claim I wrote as *"the wrapper is not uniform"*. **The rule must key on the 127 branch's exit code, not on the wrapper's presence**, or a future maintainer deleting one of the three fail-open hooks in a single release will be told by their own grep that they cannot.
- **Quoted-literal stripping.** `bash -c "git push"` and `echo "git push"` are the same syntactic shape; separating them needs a maintained wrapper allowlist (`bash -c`, `sh -lc`, `env`, `xargs`, `sudo`, `find -exec`, `npm run`, …). Every wrapper not on the list becomes an evasion channel that is closed today. **Adds mechanism and a new fail-open class.**
- **Dropping `gate-before-merge`'s `Bash|PowerShell` matcher** (recommended by the report). That arm catches `gh pr merge`, `git merge` on a protected branch, and merge-by-push — added in v2.0 precisely because *agents self-merge from their worktrees*. The hook already exits 0 unless a merge shape is found.
- **Deleting `AGENT_TEAM.md`.** See §4.1. "Zero rule citations in 820 transcripts" is the wrong-shaped measurement for a document consumed by **context injection** — injected prose is never cited by number. The evidence supports *nothing depends on it*, not *it has no value*.
- **A `FIX FIRST` heredoc phase leading the release.** Yield in shipped fail-closed gates is ~2 blocked commands per month.

---

## 7. Verification

- Gate green at every release boundary. **`test-hooks-parser-matrix.sh` (~90 min) is required only for changes to `hooks/lib/git-cmd.sh` or `json.sh`** — not for doc or template edits.
- **Every guard ships a control, and every control is verified by deleting its guard.**
- **Assert counts against an independent source** — a collector returning a partial result reads as success.
- **Check that a thing RAN, not that it returned 0.**
- **CI must move with local.** Consistency check counts are asserted in `.github/workflows/` and the CHANGELOG; deleting checks changes both.

## 8. Open risks

- **Agent deletion has no deprecation path yet** (§4.2) — the only genuine subtraction in the programme.
- **`sync-template/SKILL.md` (633 LOC)** is both the delivery mechanism for every migration and the largest unaddressed file. It has **no rehearsed `TEMPLATE_DELETED` path for a registered file carrying a PROJECT-CUSTOM region** — which is precisely why §4.1 shrinks rather than deletes.
- **One report number is unreconciled:** §2b attributes 22 `gate-before-merge` blocks to non-merge commands (`ls -la backups/`), but `gate-before-merge.sh:121` exits 0 unless a merge shape is found. Either those consumers run a pre-v2.1 hook or the block↔command join is wrong for those rows. **Do not rest any disposition on the 31% figure until this is resolved.**
