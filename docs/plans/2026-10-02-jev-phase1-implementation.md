# Jev Phase 1 (v4.4.0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let an opted-in clone route each sub-agent spawn that passes no `model` to the cheapest adequate model chosen by TypeSafe's Jev (`jev-1.13.0`, ~0.3 s), bounded to one step from the agent file's default with reviewers never below sonnet, and with zero footprint when off.

**Architecture:** model-floor's resolution moves unchanged into a new sourced-and-executable `hooks/lib/agent-model.sh`. `model-floor.sh` sources it. The user-level Jev router runs it with `bash agent-model.sh <type> <cwd>` and reads one line, so both answer "which model would this spawn get" from the same code. A new user-level skill `jev` (SKILL.md, `jev_route.py`, `jev_ctl.py`, `redact.py`, tests) writes the per-clone switch and the per-checkout `.claude/settings.local.json` registration. model-floor steps aside only when the router will really run in that checkout (R-2). With the switch off, nothing is registered and model-floor is byte-identical to the base release; a differential fixture (J-DIFF) proves it.

**Tech Stack:** bash (Git Bash on Windows), `hooks/lib/json.sh` (node, then python3, then jq), Python 3.8+ stdlib only (`urllib`, `threading`, `http.server` for the test stub, `unittest`), the system `python3` that the registration runs.

**Spec:** `docs/plans/2026-09-28-jev-phase1-design.md` (Phase 1a). Read it first. The spike this plan reuses is `G:/git/.worktrees/claude-code-toolkit/jev-phase0/spikes/jev-phase0/` (`redact.py`, `test_redact.py`, `extract_payloads.py` for the questions, `send_payloads.py` for the key loader). Never copy anything from `jev-phase0-data/`.

## Before execution (controller)

1. **v4.3.1 ships first.** Rebase `feat/jev-phase1` onto `main` at the v4.3.1 merge before Task 1 (`git -C G:/git/.worktrees/claude-code-toolkit/jev-phase1 rebase main`, after `git fetch --tags`). Then `head -1 VERSION` must print `4.3.1`. Task 1 freezes the golden model-floor from that tag. Do not start on v4.3.0.
2. After the rebase, re-find every line reference below (they are measured at 3a901fe = v4.3.0) with Grep before editing. Allocate the new check number (64 here) after the highest check v4.3.1 left, and the J-PY skip delta on top of v4.3.1's `EXP_JQ_SKIP`.
3. Spec status line: "all Jev implementation stays off mainline until the user says otherwise." Merging this branch needs the user's explicit go, not just a green gate.

## Merge risks with v4.3.1 (files both releases touch)

| File | v4.3.1 (queued: hook-timeout fail-open, `git.exe`/`"git"` recognition, a later `cd` hiding script verbs, the file-vs-registration step-aside window) | This plan |
|---|---|---|
| `hooks/model-floor.sh` + mirror | the step-aside-window note may touch its wrapper or comments | full rewrite onto the new lib (Task 2), step-aside predicate (Task 3) |
| `templates/*/.claude/settings.json`, `user-level-reference/settings.json` | likely (timeouts and wrappers) | **not touched**, but C1's registration rows (`C1_TPL`, `C1_USR`) assert their literal text |
| `hooks/lib/git-cmd.sh` | likely (`git.exe` recognition) | not touched; its `GC_KEY_PRE` definition is in the census Task 2 widens |
| `scripts/test-hooks.sh` | new blocks, tally | C1 row 6 and S-24 setup, four new blocks before the tally |
| `scripts/test-hooks-parser-matrix.sh` | `EXP_*` constants | `EXP_JQ_SKIP` + 4 |
| `scripts/verify-template-consistency.sh` | new checks (numbering) | census 21c-2a, check 63 comment, new check 64 |
| `CHANGELOG.md`, `VERSION`, `server/src/template_sync/VERSION`, sync-template `SKILL.md` marker, `README.md`, `docs/architecture.md` tables | release section and a column | release section and the next column, measured on top of v4.3.1's |
| `templates/*/AGENT_TEAM.md` (20,476 of 20,480 B) | unknown | **not touched**. The rule exception lives in the jev SKILL.md only. |

## Global Constraints

- Branch `feat/jev-phase1`, worktree `G:/git/.worktrees/claude-code-toolkit/jev-phase1`, rebased onto v4.3.1. Nothing lands on `main` without the user's explicit go.
- Every file LF. Use the Edit and Write tools only. Never write a file with a Bash heredoc (`deny-hang-shapes.sh` refuses it), and never pass non-ASCII files (CHANGELOG, README, architecture.md) through PowerShell.
- Commits: `git -C <worktree> add <explicit paths>` and `git -C <worktree> commit -F <message file outside the repo>` as separate calls, timeout 600000 (the pre-commit hook runs the whole consistency script, 58-117 s). Never `add -A`, amend, push or stash. Implementers never spawn subagents.
- Hook scripts and `hooks/lib/*` are byte-identical to `user-level-reference/hooks/` (checks 21, 21c). The template variants are not touched by this plan.
- Spec literals, verbatim:
  - config `{"model": "jev-1.13.0", "threshold": 0.8, "route": true, "legs": false}` at `<git common dir>/jev/config.json`;
  - registration `f="$HOME/.claude/skills/jev/jev_route.py"; [ -f "$f" ] && python3 "$f"; exit 0`, matcher `Agent`, `"timeout": 5`, in `.claude/settings.local.json`;
  - endpoint `POST https://api.typesafe.ai/v1/systemone`, `Authorization: Bearer <TYPESAFE_API_KEY>`, key from the environment, else `HKCU\Environment` (winreg), never in argv or a log;
  - client timeout 2 s; state = `agent_type` + `description` + `prompt`, redacted, then trimmed to 4,000 chars;
  - bounds: `|index(choice) − index(default)| ≤ 1` on `haiku < sonnet < opus < fable`, `review|architect` never below `sonnet`, `confidence ≥ threshold`;
  - output `{"hookSpecificOutput":{"hookEventName":"PreToolUse","updatedInput":{…whole tool_input…,"model":"<m>"}}}`, never with a `permissionDecision`;
  - events `<git common dir>/jev/events/<utc-ts>-<pid>.json` with `{ts, subagent_type, default, choice, confidence, probabilities, applied, reason, effort_choice, effort_confidence, latency_s}`, never the state text, never the key.
- **Tests never reach the real API.** Every Python test either injects `post` and `registry`, or runs with `JEV_TEST_MODE=1`. In that mode the registry is never read and the endpoint override is honoured only for `http://127.0.0.1`. This host holds a real key in `HKCU\Environment`, so a "no key" test that only unsets the env var would read it.
- Python: stdlib only, ≥ 3.8, `sys.dont_write_bytecode = True` at the top of every module, and tests run as `python3 -B`. A `__pycache__` in `user-level-reference/skills/jev/` would show up as drift (`verify-user-level-drift.sh` walks `find -type f`).
- The full `scripts/test-hooks.sh` takes ~10 min and stalls the shared machine. Implementers run only their own blocks with the harness from Task 1, plus `bash -n` and the Python tests. The full suite, `run-gate.sh` and the parser matrix are the controller's (Task 11), and run only with the user's go-ahead.
- Fixture blocks are delimited by `# ---- v4.4.0 <PART>:` … `# ---- end v4.4.0 <PART>`, and each one is self-contained the way C1 is: it sources `json.sh` itself and defines its own helpers.
- Fake secrets in test sources are assembled at runtime (`"xox" + "b-…"`) so that no literal token-shaped string is committed. Push protection and secret scanners must not fire on the test file.

## Plan-level refinements of the spec (flagged for the user)

- **R-1 (step 2 vs steps 6/7).** Step 2 says the spawn never inherits the orchestrator's model even when Jev fails. Steps 6/7 say "print nothing" on failure. Resolved by spawn class:
  - A *floor-class* spawn (built-in, `model: inherit`, no model) always gets an `updatedInput`: Jev's choice when every check passes, otherwise the project floor. That covers `no-key`, `egress-refused`, timeout, 5xx, garbage and any exception after resolution.
  - A *typed* spawn with its own model gets output only for a valid move that differs from that model.
- **R-2 (the switch is per clone, registration is per checkout).** v4.3.0's `model-floor.sh:88` steps aside when `<common dir>/jev/config.json` says `"route": true`. The registration, though, lives in one checkout's `.claude/settings.local.json`. Under the spec as written, a sibling worktree, a deleted skill, a missing `python3`, or the spec's `/jev off` (which removes the entry but leaves `route: true`) all leave a spawn with no emitter, and it inherits. Fix: model-floor steps aside only when all four hold: route true, `~/.claude/skills/jev/jev_route.py` exists, `python3` is on PATH, and this checkout's `settings.local.json` names the router. Separately, `/jev off` writes `"route": false` first. This deliberately changes C1 row 6 (Task 3).
- **R-3 (D2 and Non-goals vs step 2).** D2 and the Non-goals say "no `hooks/` file … nothing ships to consumers" and "off mainline". Step 2, added 2026-10-02, requires reusing model-floor's code, which means a `hooks/lib/` file shipped to every consumer, and the brief asks for a v4.4.0 release. This plan treats step 2 as superseding D2 for the shared lib only. Nothing Jev-specific ships in a template or a consumer hook. The off-mainline line is enforced as "merge needs the user's go".
- **R-4 (`CLAUDE_CODE_SUBAGENT_MODEL`).** Where that variable covers a spawn, the resolver answers `env`. The router logs `reason: "env"` and changes nothing: whether `updatedInput.model` even beats the native variable is unverified. Note that this machine's live settings set `CLAUDE_CODE_SUBAGENT_MODEL=sonnet`, so general-purpose and untyped spawns are out of Jev's reach here.
- **R-5 (full-id defaults).** A typed agent whose model is a full id (`claude-opus-4-1`) is bounded by its family (`opus`). An id with no family (`gpt-5`) gets `reason: "pinned"` and is never changed.
- **R-6 (the report's outcome join).** The spec wants routed spawns "whose agent later reported BLOCKED/NEEDS_CONTEXT, joined … from the SubagentStop retro ledger". The ledger records none of that. `hooks/retro-ledger.sh` writes a minute-resolution row only for tool_result failures (hook blocks, dead tools), never the agent's report status. `/jev report` therefore lists ledger failure rows of the same `agent_type` within 60 min after a routed spawn, and its output says that this is not report status.
- **R-7 (trim).** The spike's `trim()` returns cap + marker (~4,029 chars). The router's trim keeps the whole state, marker included, at ≤ 4,000. One Phase 0 test is tightened to match, and one test is added.
- **R-8 (`jev_ctl.py`).** The spec lists SKILL.md + `jev_route.py` + `redact.py`. On/off/status/report go in a fourth script so that `off` can restore `settings.local.json` byte for byte, which an editing model cannot guarantee. On refuses when the active `model-floor.sh` predates v4.4.0. Such a copy steps aside on the config alone, which is exactly R-2's failure.
- **R-9 (Phase 1b).** The spec names no release for 1b, and its Testing section covers 1a only. 1b is out of scope. The config still carries `"legs": false`, and `/jev on legs` prints the usage line.
- **Open question for the user, not resolved here.** `user-level-reference/CLAUDE.md:37` (and the live copy) says "Every Agent spawn names its `model` explicitly", and D5 never overrides an explicit model. Under that rule Jev routes almost nothing. The SKILL.md is `disable-model-invocation`, so its rule-exception text never reaches the orchestrator at spawn time. The live smoke (Task 11) deliberately omits `model`. Whether to amend the user-level rule is the user's call.

## Review Focus

1. **A sibling worktree of a clone where Jev is on.** It shares the config but not the registration. Its spawns must still get the floor, never inherit. Task 3, J-MF worktree rows.
2. **`/jev on` against a `settings.local.json` that already exists**, with a BOM, CRLF, or its own `Agent` hooks, or `on` run twice, then `off`. The file must come back byte-identical. If the user edited it in between, only the Jev entry is removed. Task 8.
3. **A router call that hangs**: DNS, a server that never answers, or a slow drip that defeats per-socket timeouts. The floor must still be emitted before the 5 s hook kill, from an internal deadline (3.5 s) and a joined worker thread. Task 7 E2E hang and drip rows.
4. **Event files on error paths.** An exception text or a garbage response must never put the prompt or the key into `<common dir>/jev/events/`, and `reason` is always one of `REASONS`. Task 6.
5. **Bounds on unusual defaults.** A reviewer whose own model is haiku: the role floor limits Jev's choice, never the agent's default. A full-id agent. An explicit `model`, which is never touched. Tasks 5 and 6.

## File map

| Path | Status | Responsibility |
|---|---|---|
| `hooks/lib/agent-model.sh` (+ mirror) | new | Resolution (own / floor / env / none), `am_jev_routing`, CLI line for the router |
| `hooks/model-floor.sh` (+ mirror) | rewritten | Parse the payload, call the lib, emit the floor (emitters unchanged) |
| `scripts/fixtures/model-floor-golden/model-floor.sh` | new | Frozen base-release copy for J-DIFF |
| `user-level-reference/skills/jev/SKILL.md` | new | `/jev` → runs `jev_ctl.py` |
| `user-level-reference/skills/jev/redact.py` | new | Phase 0 redactor, exact-cap trim |
| `user-level-reference/skills/jev/jev_route.py` | new | The PreToolUse router |
| `user-level-reference/skills/jev/jev_ctl.py` | new | on / off / status / report |
| `user-level-reference/skills/jev/tests/{jevtest.py,test_redact.py,test_decide.py,test_route.py,test_e2e.py,test_ctl.py}` | new | stdlib unittest, run by J-PY |
| `scripts/test-hooks.sh` | modified | Blocks J-DIFF, J-LIB, J-MF, J-PY; C1 row 6 and S-24 setup |
| `scripts/test-hooks-parser-matrix.sh` | modified | `EXP_JQ_SKIP` + 4 |
| `scripts/verify-template-consistency.sh` | modified | Census 21c-2a (3 files), check 63 comment, check 64 |
| `README.md`, `user-level-reference/README.md`, `docs/architecture.md`, `CHANGELOG.md`, `VERSION`, `server/src/template_sync/VERSION`, `user-level-reference/skills/sync-template/SKILL.md` | modified | Docs and release |

---

### Task 1: Harness, golden model-floor, and the J-DIFF regression net

**Files:**
- Create: `.superpowers/sdd/2026-10-02-jev-phase1-implementation/run-block.sh` (git-ignored by `/.superpowers/`)
- Create: `.superpowers/sdd/2026-10-02-jev-phase1-implementation/progress.md` (ledger, git-ignored)
- Create: `scripts/fixtures/model-floor-golden/model-floor.sh`
- Modify: `scripts/test-hooks.sh`, inserting the J-DIFF block directly before the final-tally line `echo "----------------------------------------------------------------"` (~:8674 at 3a901fe)

**Interfaces:**
- Produces: `bash .superpowers/sdd/2026-10-02-jev-phase1-implementation/run-block.sh <worktree> <version> <part>`, which prints `BLOCK <version> <part>: N passed, F failed, S skipped` and exits 0 iff F = 0. All later tasks use it.
- Produces: the golden file and the J-DIFF block, which Task 2 must keep green.

- [ ] **Step 1: Write the harness.** The v4.3.0 harness at `G:/git/.worktrees/claude-code-toolkit/agent-time-sinks/.superpowers/sdd/2026-09-28-agent-time-sinks-implementation/run-block.sh` hardcodes `v4.3.0` in both awk programs and the grep. Write this version-parametrised copy with the Write tool:

```bash
#!/usr/bin/env bash
# Runs ONE fixture block of scripts/test-hooks.sh with the suite's own setup
# (lines 1-50) and helper functions (every top-level function defined before
# line 400), so an implementer need not run the ~10-min full suite.
# Usage: bash run-block.sh <worktree root> <version> <part>   e.g.  ... v4.4.0 J-DIFF
# The block runs from '# ---- <version> <part>:' to '# ---- end <version> <part>'.
cd "$1" || exit 2
VER="$2"; PART="$3"
H=$(mktemp)
awk 'NR<=50{print;next} NR<400 && /^[a-z_0-9]+\(\) *\{/{f=1} f{print} f && (/^}/ || /\}[[:space:]]*(#.*)?$/ && /^[a-z_0-9]+\(\) *\{.*\}/){f=0}' scripts/test-hooks.sh > "$H"
awk -v v="$VER" -v p="$PART" 'index($0, "# ---- " v " " p ":")==1{f=1} f{print} index($0, "# ---- end " v " " p)==1{exit}' scripts/test-hooks.sh >> "$H"
if ! grep -qF "# ---- $VER $PART:" "$H"; then echo "HARNESS: block $VER $PART not found"; rm -f "$H"; exit 2; fi
printf '\necho "BLOCK %s %s: $pass passed, $fail failed, $skipped skipped"\n[ "$fail" -eq 0 ]\n' "$VER" "$PART" >> "$H"
bash "$H"; rc=$?
rm -f "$H"
exit $rc
```

- [ ] **Step 2: Record the C1 baseline**, the regression net Task 2 must reproduce exactly:

Run: `bash .superpowers/sdd/2026-10-02-jev-phase1-implementation/run-block.sh G:/git/.worktrees/claude-code-toolkit/jev-phase1 v4.3.0 C1`
Expected: `BLOCK v4.3.0 C1: N passed, 0 failed, S skipped`. Write the exact `N`/`S` line into `progress.md` under "C1 baseline (before Task 2)".

- [ ] **Step 3: Freeze the golden copy** from the base release tag:

Run: `git -C G:/git/.worktrees/claude-code-toolkit/jev-phase1 show "v$(head -1 G:/git/.worktrees/claude-code-toolkit/jev-phase1/VERSION):hooks/model-floor.sh"`, and write its output with the Write tool to `scripts/fixtures/model-floor-golden/model-floor.sh`. Then `cmp scripts/fixtures/model-floor-golden/model-floor.sh hooks/model-floor.sh`. It must be identical, because the branch has not touched model-floor yet. If `VERSION` still reads `4.3.0`, the rebase has not happened: stop and tell the controller.

- [ ] **Step 4: Write the J-DIFF block** (insert before the final tally):

```bash
# ---- v4.4.0 J-DIFF: with Jev off, model-floor answers exactly as the base release ----
# Spec D1: "zero footprint when off". From v4.4.0 model-floor.sh sources its
# resolution from lib/agent-model.sh (shared with the Jev router). With no Jev
# config, or "route": false, it must give the SAME exit code, stdout bytes and
# stderr bytes as the base release's copy, frozen in
# scripts/fixtures/model-floor-golden/model-floor.sh, for every payload class
# C1 exercises. Self-contained: run-block.sh carries only the suite helpers.
echo "=== model-floor vs the base release (v4.4.0 J-DIFF) ==="
. "$ROOT/hooks/lib/json.sh"
JD_BASH=$(command -v bash)
unset CLAUDE_CODE_SUBAGENT_MODEL CLAUDE_CODE_SUBAGENT_MODEL_FORCE
JDG="$TMPROOT/jd-gold"; mkdir -p "$JDG/lib"
cp "$ROOT/scripts/fixtures/model-floor-golden/model-floor.sh" "$JDG/model-floor.sh"
cp "$ROOT/hooks/lib/json.sh" "$JDG/lib/json.sh"
JDR=$(mkrepo jdrepo main)
JDH="$TMPROOT/jdhome"
mkdir -p "$JDR/.claude/agents/team" "$JDH/.claude/agents/sub"
printf -- '---\nname: typed\nmodel: haiku\n---\n'              > "$JDR/.claude/agents/typed.md"
printf -- '---\nname: inh\nmodel: inherit\n---\n'              > "$JDR/.claude/agents/inh.md"
printf -- '---\r\nname: inhcrlf\r\nmodel: inherit\r\n---\r\n'  > "$JDR/.claude/agents/inhcrlf.md"
printf -- '---\nname: fullid\nmodel: claude-opus-4-1\n---\n'   > "$JDR/.claude/agents/fullid.md"
printf -- '---\nname: nomodel\ndescription: x\n---\n'          > "$JDR/.claude/agents/nomodel.md"
printf -- '---\nname: code-reviewer\nmodel: opus\n---\n'       > "$JDR/.claude/agents/reviewer-file.md"
printf -- '---\nname: nested\nmodel: opus\n---\n'              > "$JDR/.claude/agents/team/nested.md"
printf -- '---\ndescription: no name key\nmodel: haiku\n---\n' > "$JDR/.claude/agents/fbonly.md"
printf '\357\273\277---\nname: bomagent\nmodel: opus\n---\n'   > "$JDR/.claude/agents/bom-file.md"
printf -- '---\nname: uagent\nmodel: opus\n---\n'              > "$JDH/.claude/agents/uagent.md"
printf -- '---\nname: homeinh\nmodel: inherit\n---\n'          > "$JDH/.claude/agents/sub/w.md"
JDCWD=$(natpath "$JDR")
JDPROMPT=$'Do it \xe2\x80\x94 "quoted"\nline two'
jd_payload() { # <type|-> <model|-> -> an Agent payload; '-' = key absent
  jdt=""; [ "$1" = "-" ] || jdt="\"subagent_type\":\"$(jesc "$1")\","
  jdm=""; [ "$2" = "-" ] || jdm="\"model\":\"$(jesc "$2")\","
  printf '{"session_id":"t","hook_event_name":"PreToolUse","tool_name":"Agent","tool_input":{%s%s"prompt":"%s","description":"d","zz_unknown":1},"cwd":"%s"}' \
    "$jdt" "$jdm" "$(jesc "$JDPROMPT")" "$(jesc "$JDCWD")"
}
jd_cmp() { # <label> <payload> -- golden vs current: exit code, stdout bytes, stderr bytes
  printf '%s' "$2" | HOME="$JDH" "$JD_BASH" "$JDG/model-floor.sh"       >"$TMPROOT/jd.go" 2>"$TMPROOT/jd.ge"; jd_grc=$?
  printf '%s' "$2" | HOME="$JDH" "$JD_BASH" "$ROOT/hooks/model-floor.sh" >"$TMPROOT/jd.co" 2>"$TMPROOT/jd.ce"; jd_crc=$?
  expect "J-DIFF $1: exit code"        "$jd_grc" "$jd_crc"
  expect "J-DIFF $1: stdout identical" same "$(cmp -s "$TMPROOT/jd.go" "$TMPROOT/jd.co" && echo same || echo differs)"
  expect "J-DIFF $1: stderr identical" same "$(cmp -s "$TMPROOT/jd.ge" "$TMPROOT/jd.ce" && echo same || echo differs)"
}
# Two-sided: the comparison is not vacuous -- the golden copy really emits for
# a floored type and really stays silent for a typed one.
jd_cmp "general-purpose" "$(jd_payload general-purpose -)"
expect "J-DIFF probe: the golden copy emits for general-purpose" sonnet "$(jfield "$(<"$TMPROOT/jd.go")" hookSpecificOutput.updatedInput.model)"
jd_cmp "typed" "$(jd_payload typed -)"
expect "J-DIFF probe: the golden copy is silent for a typed agent" 0 "$(wc -c < "$TMPROOT/jd.go" | tr -d ' ')"
for jd_t in - Plan Explore claude inh inhcrlf nomodel homeinh fullid uagent code-reviewer nested fbonly bomagent mystery plug:agent statusline-setup claude-code-guide fork ../x .hidden; do
  jd_cmp "type $jd_t" "$(jd_payload "$jd_t" -)"
done
jd_cmp "explicit model"           "$(jd_payload general-purpose opus)"
jd_cmp "not the Agent tool"       "$(mkjson Bash 'echo hi' "$JDCWD")"
jd_cmp "invalid JSON"             'not json at all'
jd_cmp "empty stdin"              ''
jd_cmp "tool_input not an object" '{"tool_name":"Agent","tool_input":"a string","cwd":"."}'
printf '# ctx\n- **Subagent default model**: haiku\n' > "$JDR/PROJECT_CONTEXT.md"
jd_cmp "PROJECT_CONTEXT haiku" "$(jd_payload general-purpose -)"
printf '\357\273\277- **Subagent default model**: opus\n' > "$JDR/PROJECT_CONTEXT.md"
jd_cmp "PROJECT_CONTEXT BOM on line 1" "$(jd_payload general-purpose -)"
printf '# ctx\n- **Subagent default model**: {{SUBAGENT_DEFAULT_MODEL}}\n' > "$JDR/PROJECT_CONTEXT.md"
jd_cmp "PROJECT_CONTEXT placeholder" "$(jd_payload general-purpose -)"
printf '# ctx\n<!-- - **Subagent default model**: opus -->\n' > "$JDR/PROJECT_CONTEXT.md"
jd_cmp "PROJECT_CONTEXT commented example" "$(jd_payload general-purpose -)"
rm -f "$JDR/PROJECT_CONTEXT.md"
export CLAUDE_CODE_SUBAGENT_MODEL=haiku
jd_cmp "env haiku, general-purpose" "$(jd_payload general-purpose -)"
jd_cmp "env haiku, Plan"            "$(jd_payload Plan -)"
export CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1
jd_cmp "env haiku + FORCE, Plan"    "$(jd_payload Plan -)"
export CLAUDE_CODE_SUBAGENT_MODEL=inherit
jd_cmp "env inherit + FORCE, Plan"  "$(jd_payload Plan -)"
unset CLAUDE_CODE_SUBAGENT_MODEL CLAUDE_CODE_SUBAGENT_MODEL_FORCE
JDGD=$(git -C "$JDR" rev-parse --path-format=absolute --git-common-dir)
mkdir -p "$JDGD/jev"; printf '{"route": false}\n' > "$JDGD/jev/config.json"
jd_cmp "jev config route false" "$(jd_payload general-purpose -)"
rm -rf "$JDGD/jev"
# ---- end v4.4.0 J-DIFF
```

- [ ] **Step 5: Run it.** It is green from the start, since the two files are identical; it proves the net is wired.

Run: `bash .superpowers/sdd/2026-10-02-jev-phase1-implementation/run-block.sh G:/git/.worktrees/claude-code-toolkit/jev-phase1 v4.4.0 J-DIFF`
Expected: `BLOCK v4.4.0 J-DIFF: 113 passed, 0 failed, 0 skipped`, which is 37 `jd_cmp` rows × 3 plus the 2 probes. Then do a red-side check: temporarily append `echo x >&2` to a scratch copy of the golden file (in `$TMPROOT`, never the real fixture), point `JDG` at it, and see the stderr rows FAIL. Revert. Record the pass count in `progress.md`.

- [ ] **Step 6: Commit** (`test(v4.4.0): J-DIFF -- model-floor vs the frozen base-release copy (zero footprint when off)`). Paths: `scripts/fixtures/model-floor-golden/model-floor.sh scripts/test-hooks.sh`.

---

### Task 2: `hooks/lib/agent-model.sh`, model-floor's resolution moved unchanged

**Files:**
- Create: `hooks/lib/agent-model.sh`; copy it to `user-level-reference/hooks/lib/agent-model.sh`
- Modify: `hooks/model-floor.sh` (full rewrite below); copy it to `user-level-reference/hooks/model-floor.sh`
- Modify: `scripts/test-hooks.sh`:
  - C1 S-24 temp-HOME setup (~:8490-8492): add ONE `cp`;
  - new J-LIB block after J-DIFF.
- Modify: `scripts/verify-template-consistency.sh`:
  - census 21c-2a (~:998-1011): the files are now git-cmd.sh, run-gate.sh and agent-model.sh;
  - check 63 comment (~:3932-3948).

**Interfaces:**
- Produces, when sourced: `am_env_forced` (rc 0/1); `am_resolve <type> <cwd>`, which sets `AM_KIND` (`own|floor|env|none`), `AM_MODEL`, `AM_EFFORT`, `AM_ROOT`; `am_jev_routing <root>` (rc 0 = step aside), which sets `AM_GD`.
- Produces, when executed: `bash agent-model.sh <type> <cwd>` prints exactly one line, `<kind> <model|-> <jev 0|1> <effort|-> <git common dir|->`. The last field may contain spaces. Task 7's `run_resolver` parses it with `^(own|floor|env|none) (\S+) ([01]) (\S+) (.+)$`.

- [ ] **Step 1: Write the J-LIB block** (after `# ---- end v4.4.0 J-DIFF`):

```bash
# ---- v4.4.0 J-LIB: hooks/lib/agent-model.sh, the resolver model-floor and the Jev router share ----
echo "=== hooks/lib/agent-model.sh (v4.4.0 J-LIB) ==="
unset CLAUDE_CODE_SUBAGENT_MODEL CLAUDE_CODE_SUBAGENT_MODEL_FORCE
JLR=$(mkrepo jlrepo main)
JLH="$TMPROOT/jlhome"; mkdir -p "$JLH/.claude/agents" "$JLR/.claude/agents"
printf -- '---\nname: typed\nmodel: haiku\neffort: high\n---\n' > "$JLR/.claude/agents/typed.md"
printf -- '---\nname: inh\nmodel: inherit\n---\n'                > "$JLR/.claude/agents/inh.md"
printf -- '---\nname: fullid\nmodel: "claude-opus-4-1"\n---\n'    > "$JLR/.claude/agents/fullid.md"
printf -- '---\nname: uagent\nmodel: opus\n---\n'                 > "$JLH/.claude/agents/uagent.md"
JLCWD=$(natpath "$JLR")
JLGD=$(git -C "$JLR" rev-parse --path-format=absolute --git-common-dir)
jl_cli() { HOME="$JLH" bash "$ROOT/hooks/lib/agent-model.sh" "$1" "$JLCWD" | cut -d' ' -f1-4; }
expect "J-LIB general-purpose -> floor"            "floor sonnet 0 -"        "$(jl_cli general-purpose)"
expect "J-LIB empty type = general-purpose"        "floor sonnet 0 -"        "$(jl_cli '')"
expect "J-LIB Plan (built-in, no file) -> floor"   "floor sonnet 0 -"        "$(jl_cli Plan)"
expect "J-LIB inherit agent -> floor"              "floor sonnet 0 -"        "$(jl_cli inh)"
expect "J-LIB typed agent -> own, with its effort" "own haiku 0 high"        "$(jl_cli typed)"
expect "J-LIB full id, quotes stripped -> own"     "own claude-opus-4-1 0 -" "$(jl_cli fullid)"
expect "J-LIB user-level agent -> own"             "own opus 0 -"            "$(jl_cli uagent)"
expect "J-LIB unknown type, no file -> none"       "none - 0 -"              "$(jl_cli mystery)"
expect "J-LIB statusline-setup -> none"            "none - 0 -"              "$(jl_cli statusline-setup)"
expect "J-LIB path-unsafe type -> none"            "none - 0 -"              "$(jl_cli '../x')"
JLINJ="$TMPROOT/jl-injected"
expect "J-LIB a hostile type is data, not code"    "none - 0 -"              "$(jl_cli "\$(touch $JLINJ)")"
expect "J-LIB the hostile type ran nothing"        0 "$([ -e "$JLINJ" ] && echo 1 || echo 0)"
printf '# ctx\n- **Subagent default model**: haiku\n' > "$JLR/PROJECT_CONTEXT.md"
expect "J-LIB project default haiku"               "floor haiku 0 -"         "$(jl_cli general-purpose)"
rm -f "$JLR/PROJECT_CONTEXT.md"
export CLAUDE_CODE_SUBAGENT_MODEL=haiku
expect "J-LIB env default covers general-purpose"  "env - 0 -"               "$(jl_cli general-purpose)"
expect "J-LIB env default does not cover Plan"     "floor sonnet 0 -"        "$(jl_cli Plan)"
export CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1
expect "J-LIB env default + FORCE covers Plan"     "env - 0 -"               "$(jl_cli Plan)"
unset CLAUDE_CODE_SUBAGENT_MODEL CLAUDE_CODE_SUBAGENT_MODEL_FORCE
expect "J-LIB 5th field is the git common dir"     "$JLGD" "$(HOME="$JLH" bash "$ROOT/hooks/lib/agent-model.sh" general-purpose "$JLCWD" | cut -d' ' -f5-)"
expect "J-LIB exactly one output line"             1 "$(HOME="$JLH" bash "$ROOT/hooks/lib/agent-model.sh" Plan "$JLCWD" | wc -l | tr -d ' ')"
expect "J-LIB mirror is byte-identical"            same "$(cmp -s "$ROOT/hooks/lib/agent-model.sh" "$ROOT/user-level-reference/hooks/lib/agent-model.sh" && echo same || echo differs)"
# ---- end v4.4.0 J-LIB
```

- [ ] **Step 2: Run it and watch it fail.** Run: `bash .superpowers/sdd/2026-10-02-jev-phase1-implementation/run-block.sh G:/git/.worktrees/claude-code-toolkit/jev-phase1 v4.4.0 J-LIB`. Expected: every row that reads the CLI's output FAILs, plus the mirror row (`bash: …/agent-model.sh: No such file or directory`). Only "the hostile type ran nothing" passes.

- [ ] **Step 3: Create `hooks/lib/agent-model.sh`.** The body is v4.3.0's `model-floor.sh` lines 28-90, renamed `mf_`→`am_` and wrapped in functions:

```bash
# shellcheck shell=bash
# agent-model.sh -- the model an Agent spawn WITHOUT an explicit `model` runs on
# (v4.4.0; the logic is v4.3.0's model-floor.sh, moved here unchanged).
#
# Two callers, one answer (Jev Phase 1 spec, step 2: the router "reuses
# model-floor's resolution code rather than re-deriving it"):
#   - hooks/model-floor.sh SOURCES it: am_resolve, then am_jev_routing;
#   - the user-level Jev router (~/.claude/skills/jev/jev_route.py) RUNS it:
#       bash agent-model.sh <subagent_type> <cwd>
#     and reads ONE line: "<kind> <model|-> <jev 0|1> <effort|-> <git common dir|->".
#     Arguments are data: a type outside [A-Za-z0-9_.-] resolves to `none`.
# kind: own   -- the agent file sets a model (an alias or a full id): its choice
#       floor -- no model of its own (`inherit`, none, or a known inheriting
#                built-in with no file): **Subagent default model**, else sonnet
#       env   -- CLAUDE_CODE_SUBAGENT_MODEL holds a real model and covers this
#                spawn (S-23/S-30): the native default wins, nobody rewrites
#       none  -- a self-modelled built-in, a type no visible file defines, or an
#                unsafe name: change nothing
# Agent identity (S-22): the frontmatter `name:`, .claude/agents/ scanned
# recursively, project before user level, filename as the fallback.
# No JSON parser needed: it reads frontmatter and PROJECT_CONTEXT.md only.
# Mirrored byte-identically at user-level-reference/hooks/lib/ (check 21c).

# S-23/S-30: CLAUDE_CODE_SUBAGENT_MODEL is a native default only when it holds a
# REAL model (an alias or a full claude-* id); `inherit` or empty means unset.
AM_ENV_REAL=""
case "${CLAUDE_CODE_SUBAGENT_MODEL:-}" in haiku|sonnet|opus|fable|claude-*) AM_ENV_REAL=1 ;; esac
# am_env_forced -- with CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1 the variable covers
# every spawn. Without FORCE it covers only general-purpose and an untyped spawn.
am_env_forced() { [ -n "$AM_ENV_REAL" ] && [ "${CLAUDE_CODE_SUBAGENT_MODEL_FORCE:-}" = 1 ]; }

# GC_BOM / GC_KEY_PRE: the same text as hooks/lib/git-cmd.sh and run-gate.sh,
# pinned together by the definition census (check 21c-2a). Sourcing git-cmd.sh
# here would cost ~57 ms per Agent spawn. A BOM on line 1 must not hide the key.
GC_BOM=$(printf '\357\273\277')
GC_KEY_PRE="^(${GC_BOM})?[-*[:space:]]*"

# am_fm <file> <key> -- a frontmatter value, unquoted, no whitespace, CR and a
# leading BOM tolerated. Empty when the key (or the frontmatter) is absent.
am_fm() { awk -v k="$2" -v bom="$GC_BOM" 'NR==1&&index($0,bom)==1{$0=substr($0,length(bom)+1)} NR==1&&/^---/{f=1;next} f&&/^---/{exit} f&&index($0,k":")==1{sub(/^[^:]*:[[:space:]]*/,"");print;exit}' "$1" 2>/dev/null | tr -d '\r"'"'"'[:space:]'; }
# am_find <agents dir> <type> -- the first *.md under it (recursively) whose
# frontmatter name equals <type>. grep narrows the candidates; am_fm confirms the
# name is really in the frontmatter (a `name:` line in a body does not count).
am_find() {
  [ -d "$1" ] || return 0
  grep -rlE "^name:[[:space:]]*[\"']?${2}[\"']?[[:space:]]*\$" --include='*.md' "$1" 2>/dev/null | while IFS= read -r am_c; do
    if [ "$(am_fm "$am_c" name)" = "$2" ]; then printf '%s\n' "$am_c"; break; fi
  done | head -1
}

# am_resolve <type> <cwd> -- sets AM_KIND, AM_MODEL, AM_EFFORT, AM_ROOT.
# AM_ROOT stays empty on the early `env`/`none` answers (no git call needed).
am_resolve() {
  AM_KIND=none; AM_MODEL=""; AM_EFFORT=""; AM_ROOT=""
  am_t=${1:-general-purpose}
  am_env_forced && { AM_KIND=env; return 0; }
  [ -n "$AM_ENV_REAL" ] && [ "$am_t" = general-purpose ] && { AM_KIND=env; return 0; }
  case "$am_t" in *[!A-Za-z0-9_.-]*|.*) return 0 ;; esac
  # Types that carry a model of their own (statusline-setup: sonnet,
  # claude-code-guide: haiku) or ignore a model override (fork).
  case "$am_t" in statusline-setup|claude-code-guide|fork) return 0 ;; esac
  AM_ROOT=$(git -C "${2:-.}" rev-parse --show-toplevel 2>/dev/null) || AM_ROOT=${2:-.}
  am_file=""
  for am_d in "$AM_ROOT/.claude/agents" "$HOME/.claude/agents"; do
    am_file=$(am_find "$am_d" "$am_t")
    [ -n "$am_file" ] && break
  done
  if [ -z "$am_file" ]; then
    for am_f in "$AM_ROOT/.claude/agents/$am_t.md" "$HOME/.claude/agents/$am_t.md"; do
      [ -f "$am_f" ] && { am_file=$am_f; break; }
    done
  fi
  if [ -n "$am_file" ]; then
    AM_EFFORT=$(am_fm "$am_file" effort)
    AM_MODEL=$(am_fm "$am_file" model)
    # Any model of its own -- an alias or a full id -- is the agent's choice;
    # only `inherit` (or none) falls through to the floor.
    case "$AM_MODEL" in ""|inherit) AM_MODEL="" ;; *) AM_KIND=own; return 0 ;; esac
  else
    # No file: only the known inheriting built-ins. Anything else may be defined
    # where this cannot look (--agents, managed settings, a plugin): do nothing.
    case "$am_t" in general-purpose|Plan|Explore|claude) ;; *) return 0 ;; esac
  fi
  AM_MODEL=$(grep -E "${GC_KEY_PRE}\*\*Subagent default model\*\*:" "$AM_ROOT/PROJECT_CONTEXT.md" 2>/dev/null | head -1 | sed -E 's/.*\*\*Subagent default model\*\*:[[:space:]]*//; s/[`[:space:]]//g')
  case "$AM_MODEL" in haiku|sonnet|opus|fable) ;; *) AM_MODEL=sonnet ;; esac
  AM_KIND=floor
}

# am_jev_routing <root> -- exit 0 iff model-floor must step aside for the Jev
# router in this checkout. Sets AM_GD (the absolute git common dir) either way.
am_jev_routing() {
  AM_GD=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
  [ -n "$AM_GD" ] || return 1
  grep -Eq '"route"[[:space:]]*:[[:space:]]*true' "$AM_GD/jev/config.json" 2>/dev/null
}

# Executed (the Jev router), not sourced: print the one-line answer.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  am_resolve "${1:-}" "${2:-.}"
  [ -n "$AM_ROOT" ] || AM_ROOT=$(git -C "${2:-.}" rev-parse --show-toplevel 2>/dev/null) || AM_ROOT=${2:-.}
  if am_jev_routing "$AM_ROOT"; then am_j=1; else am_j=0; fi
  printf '%s %s %s %s %s\n' "$AM_KIND" "${AM_MODEL:--}" "$am_j" "${AM_EFFORT:--}" "${AM_GD:--}"
fi
```

- [ ] **Step 4: Rewrite `hooks/model-floor.sh`.** Keep v4.3.0's lines 1-22 (the header comment) verbatim. Add this paragraph after them, then replace lines 23-90 with the code below, and keep lines 91-131 (the emitters and stderr line) byte-identical:

```bash
#
# v4.4.0: the resolution (agent identity, the env step-aside, the built-in list,
# the project default) lives in lib/agent-model.sh, shared with the optional Jev
# router so both answer the same question the same way. With Jev off this hook
# is byte-for-byte the base release in behaviour: scripts/test-hooks.sh J-DIFF.
lib="$(dirname "$0")/lib/json.sh"
[ -f "$lib" ] || exit 0
# shellcheck source=lib/json.sh
. "$lib"
amlib="$(dirname "$0")/lib/agent-model.sh"
[ -f "$amlib" ] || exit 0
# shellcheck source=lib/agent-model.sh
. "$amlib"
MF_JSON=$(cat)
am_env_forced && exit 0
case "$MF_JSON" in "$JSON_BOM"*) MF_JSON=${MF_JSON#"$JSON_BOM"} ;; esac
json_have || exit 0
json_valid "$MF_JSON" || exit 0
[ "$(json_get "$MF_JSON" tool_name)" = "Agent" ] || exit 0
[ -n "$(json_get "$MF_JSON" tool_input.model)" ] && exit 0
MF_TYPE=$(json_get "$MF_JSON" tool_input.subagent_type)
[ -n "$MF_TYPE" ] || MF_TYPE=general-purpose
MF_CWD=$(json_get "$MF_JSON" cwd); [ -n "$MF_CWD" ] || MF_CWD=.
am_resolve "$MF_TYPE" "$MF_CWD"
[ "$AM_KIND" = floor ] || exit 0
am_jev_routing "$AM_ROOT" && exit 0
MF_DEF=$AM_MODEL
```

Then mirror both files: `cp hooks/lib/agent-model.sh user-level-reference/hooks/lib/agent-model.sh` and `cp hooks/model-floor.sh user-level-reference/hooks/model-floor.sh`.

- [ ] **Step 5: The one allowed C1 edit.** The S-24 case (b) installs a user-level copy under a temp HOME. That copy now needs the lib, or it goes silent and the row "C1 S-24 user-level wrapper, no project copy -> runs" fails. After the line `cp "$ROOT/user-level-reference/hooks/lib/json.sh"    "$C1UH/.claude/hooks/lib/json.sh"` (~:8492) add:

```bash
  cp "$ROOT/user-level-reference/hooks/lib/agent-model.sh" "$C1UH/.claude/hooks/lib/agent-model.sh"
```

No other C1 line changes in this task. A changed expectation would be a regression.

- [ ] **Step 6: Widen the definition census** (21c-2a, ~:998-1011). Replace the loop and its two messages with:

```bash
GC_KEY_PRE_DEF='GC_KEY_PRE="^(${GC_BOM})?[-*[:space:]]*"'
gkp_have=0
for gkf in hooks/lib/git-cmd.sh hooks/run-gate.sh hooks/lib/agent-model.sh; do
  grep -qF "$GC_KEY_PRE_DEF" "$gkf" && gkp_have=$((gkp_have + 1))
done
if [ "$gkp_have" -eq 3 ]; then
  ok "GC_KEY_PRE defined identically in git-cmd.sh, the standalone run-gate.sh and agent-model.sh"
else
  ko "GC_KEY_PRE definition drifted: found in $gkp_have of 3 files (git-cmd.sh, run-gate.sh, agent-model.sh)"
fi
```

Also edit the comment above it to say that `agent-model.sh` repeats the definition (one sourced git call per Agent spawn is the cost it avoids). In the check 63 comment (~:3936 and ~:3947-3948), change the readers list `model-floor.sh` → `lib/agent-model.sh`, and change "the same text as hooks/lib/git-cmd.sh, run-gate.sh and model-floor.sh (the definition census above pins the copies together)" → "the same text as hooks/lib/git-cmd.sh, run-gate.sh and lib/agent-model.sh (the definition census, check 21c-2a, pins the three copies together)". That claim was false at v4.3.0: the census never covered model-floor.sh.

- [ ] **Step 7: Verify the refactor reproduced everything.**

Run, in order:
- `bash -n hooks/lib/agent-model.sh && bash -n hooks/model-floor.sh`
- `cmp hooks/lib/agent-model.sh user-level-reference/hooks/lib/agent-model.sh && cmp hooks/model-floor.sh user-level-reference/hooks/model-floor.sh`
- `run-block.sh … v4.4.0 J-LIB`. Expected: 19 passed, 0 failed.
- `run-block.sh … v4.4.0 J-DIFF`. Expected: the Task 1 count, 0 failed.
- `run-block.sh … v4.3.0 C1`. Expected: **exactly** the baseline line recorded in `progress.md` (same passed and skipped).
- `bash scripts/verify-template-consistency.sh 2>&1 | tail -3`. Expected: `ALL CHECKS PASSED`. Also grep its output for `GC_KEY_PRE defined identically` and `agent-model.sh is mirrored`.

- [ ] **Step 8: Check that the new lib reaches consumers with no list to update.** Confirm with Grep that every place copying hooks walks `hooks/` recursively: `setup-project.sh:849-859` (`find "$SCRIPT_DIR/hooks" -type f`), `setup-project.ps1:550-556` (`Get-ChildItem -Recurse`), `templates/ownership.json` (`"hooks/**"`), `server/src/template_sync/mcp.py:483` (root-tracked `hooks/**` "recursively, including lib/"). If any of these enumerates files by name after the rebase, add `hooks/lib/agent-model.sh` there, and tell the controller.

- [ ] **Step 9: Commit** (`refactor(hooks): model-floor's resolution moves to hooks/lib/agent-model.sh for the Jev router to reuse (v4.4.0)`). Paths: `hooks/lib/agent-model.sh hooks/model-floor.sh user-level-reference/hooks/lib/agent-model.sh user-level-reference/hooks/model-floor.sh scripts/test-hooks.sh scripts/verify-template-consistency.sh`.

---

### Task 3: model-floor steps aside only for a router that will run (R-2)

**Files:**
- Modify: `hooks/lib/agent-model.sh` (`am_jev_routing` + `AM_JEV_MARKER`) and its mirror
- Modify: `hooks/model-floor.sh` header line "Steps aside while Jev routing is on (it applies the same floor)" and its mirror
- Modify: `scripts/test-hooks.sh`:
  - C1 row 6 (~:8438-8444), a deliberate change;
  - new J-MF block after J-LIB.

**Interfaces:**
- Produces: `AM_JEV_MARKER='skills/jev/jev_route.py'` as a line of its own, which check 64 (Task 9) extracts. `am_jev_routing <root>` requires route true, the router file, `python3`, and the marker in `<root>/.claude/settings.local.json`.
- Consumes: Task 2's lib.

- [ ] **Step 1: Write the J-MF block** (after `# ---- end v4.4.0 J-LIB`):

```bash
# ---- v4.4.0 J-MF: model-floor steps aside only for a router that will run (R-2) ----
# v4.3.0 stepped aside on "route": true alone. The switch is per CLONE (the
# common git dir) but the registration is per CHECKOUT (.claude/settings.local.json),
# so a sibling worktree, a deleted skill or a missing python3 left a spawn with
# NO emitter -- it inherited the orchestrator's model. Now all four must hold.
echo "=== model-floor step-aside (v4.4.0 J-MF) ==="
. "$ROOT/hooks/lib/json.sh"
unset CLAUDE_CODE_SUBAGENT_MODEL CLAUDE_CODE_SUBAGENT_MODEL_FORCE
JMR=$(mkrepo jmrepo main)
JMH="$TMPROOT/jmhome"; mkdir -p "$JMH/.claude/skills/jev" "$JMR/.claude"
JMGD=$(git -C "$JMR" rev-parse --path-format=absolute --git-common-dir)
JMREG='{"hooks":{"PreToolUse":[{"matcher":"Agent","hooks":[{"type":"command","command":"f=\"$HOME/.claude/skills/jev/jev_route.py\"; [ -f \"$f\" ] && python3 \"$f\"; exit 0","timeout":5}]}]}}'
# With python3 hidden (the jq-only matrix configuration) the router cannot run,
# so the "fully on" rows expect the floor there -- one assertion either way.
JM_ON=silent; command -v python3 >/dev/null 2>&1 || JM_ON=sonnet
jm_model() { # <cwd> -> the model model-floor emits for a general-purpose spawn, or "silent"
  printf '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","prompt":"p"},"cwd":"%s"}' "$(jesc "$(natpath "$1")")" \
    | HOME="$JMH" bash "$ROOT/hooks/model-floor.sh" >"$TMPROOT/jm.out" 2>/dev/null
  if [ -s "$TMPROOT/jm.out" ]; then jfield "$(<"$TMPROOT/jm.out")" hookSpecificOutput.updatedInput.model; else echo silent; fi
}
jm_state() { # <route true|false|absent> <router file yes|no> <registered yes|no|other>
  rm -rf "$JMGD/jev"
  [ "$1" = absent ] || { mkdir -p "$JMGD/jev"; printf '{"route": %s}\n' "$1" > "$JMGD/jev/config.json"; }
  rm -f "$JMH/.claude/skills/jev/jev_route.py"; [ "$2" = yes ] && : > "$JMH/.claude/skills/jev/jev_route.py"
  case "$3" in
    yes)   printf '%s\n' "$JMREG" > "$JMR/.claude/settings.local.json" ;;
    other) printf '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"echo mine"}]}]}}\n' > "$JMR/.claude/settings.local.json" ;;
    *)     rm -f "$JMR/.claude/settings.local.json" ;;
  esac
}
jm_state true yes yes;   expect "J-MF on: route, router, registration -> model-floor silent" "$JM_ON" "$(jm_model "$JMR")"
jm_state true yes no;    expect "J-MF this checkout not registered -> floor"                  sonnet "$(jm_model "$JMR")"
jm_state true yes other; expect "J-MF settings.local.json without the router -> floor"        sonnet "$(jm_model "$JMR")"
jm_state true no yes;    expect "J-MF router file deleted -> floor"                          sonnet "$(jm_model "$JMR")"
jm_state false yes yes;  expect "J-MF /jev off (route false) -> floor"                       sonnet "$(jm_model "$JMR")"
jm_state absent yes yes; expect "J-MF no config at all -> floor"                             sonnet "$(jm_model "$JMR")"
# A sibling worktree shares the clone's config but not the checkout's settings.
JMWT="$TMPROOT/jmwt"
git -C "$JMR" worktree add -q -b jmwt "$JMWT" >/dev/null 2>&1
jm_state true yes yes
expect "J-MF worktree shares the common dir"           "$JMGD" "$(git -C "$JMWT" rev-parse --path-format=absolute --git-common-dir)"
expect "J-MF sibling worktree, unregistered -> floor"  sonnet  "$(jm_model "$JMWT")"
expect "J-MF main checkout, registered -> on"          "$JM_ON" "$(jm_model "$JMR")"
JM_CLI_ON=1; [ "$JM_ON" = silent ] || JM_CLI_ON=0
expect "J-MF lib CLI jev field, registered checkout"   "$JM_CLI_ON" "$(HOME="$JMH" bash "$ROOT/hooks/lib/agent-model.sh" general-purpose "$(natpath "$JMR")" | cut -d' ' -f3)"
expect "J-MF lib CLI jev field, sibling worktree"      0 "$(HOME="$JMH" bash "$ROOT/hooks/lib/agent-model.sh" general-purpose "$(natpath "$JMWT")" | cut -d' ' -f3)"
rm -rf "$JMGD/jev"
# ---- end v4.4.0 J-MF
```

- [ ] **Step 2: Run it and watch it fail.** `run-block.sh … v4.4.0 J-MF`. Expected FAILs: "this checkout not registered", "settings.local.json without the router", "router file deleted", "sibling worktree" (v4.3.0 semantics answer `silent` there), and "lib CLI jev field, sibling worktree" (answers 1).

- [ ] **Step 3: Tighten `am_jev_routing`.** Replace the Task 2 function with:

```bash
# AM_JEV_MARKER -- the path every /jev registration names. Check 64 asserts the
# registration jev_ctl.py writes (REG_COMMAND) contains it.
AM_JEV_MARKER='skills/jev/jev_route.py'
# am_jev_routing <root> -- exit 0 iff the Jev router WILL run for a spawn in this
# checkout, so model-floor may step aside (v4.4.0 R-2). All four must hold:
#   1. <git common dir>/jev/config.json says "route": true      (/jev on, per clone)
#   2. ~/.claude/skills/jev/jev_route.py exists                  (a deleted skill is silent)
#   3. python3 is on PATH                                        (the registration runs it)
#   4. <root>/.claude/settings.local.json names the router       (per CHECKOUT: a sibling
#      worktree of the same clone has its own settings.local.json)
# Any one missing -> model-floor floors, so a spawn never has neither emitter.
# Sets AM_GD (the absolute git common dir) whenever git answers.
am_jev_routing() {
  AM_GD=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
  [ -n "$AM_GD" ] || return 1
  grep -Eq '"route"[[:space:]]*:[[:space:]]*true' "$AM_GD/jev/config.json" 2>/dev/null || return 1
  [ -f "$HOME/.claude/skills/jev/jev_route.py" ] || return 1
  command -v python3 >/dev/null 2>&1 || return 1
  grep -qF "$AM_JEV_MARKER" "$1/.claude/settings.local.json" 2>/dev/null
}
```

In `hooks/model-floor.sh`'s header, change "Steps aside while Jev routing is on (it applies the same floor)" to "Steps aside while the Jev router will run in this checkout (it applies the same floor; see am_jev_routing in lib/agent-model.sh)". Mirror both files.

- [ ] **Step 4: Amend C1 row 6 deliberately.** Its old premise, "route true alone means step aside", is exactly what R-2 removes. Replace the lines from `# row 6: Jev routing on -> step aside` through `rm -rf "$C1GD/jev"` (~:8438-8444) with:

```bash
# row 6: Jev routing on -> step aside. v4.4.0 R-2: only when the router will
# really run -- route true AND ~/.claude/skills/jev/jev_route.py AND python3 AND
# this checkout's settings.local.json registers it (J-MF has the negative rows).
# One assertion on every host: without python3 the expected answer is the floor.
C1GD=$(git -C "$C1R" rev-parse --path-format=absolute --git-common-dir)
mkdir -p "$C1GD/jev" "$C1HOME/.claude/skills/jev"; printf '{"route": true}\n' > "$C1GD/jev/config.json"
: > "$C1HOME/.claude/skills/jev/jev_route.py"
printf '{"hooks":{"PreToolUse":[{"matcher":"Agent","hooks":[{"type":"command","command":"python3 ~/.claude/skills/jev/jev_route.py"}]}]}}\n' > "$C1R/.claude/settings.local.json"
c1_run - "$C1HOME" "$(c1_payload general-purpose - "$C1CWD")"
C1_R6=silent; command -v python3 >/dev/null 2>&1 || C1_R6=sonnet
expect "C1 row6 jev router installed+registered -> silent (floor without python3)" "$C1_R6" \
  "$(if [ -s "$C1OUTF" ]; then jfield "$(<"$C1OUTF")" hookSpecificOutput.updatedInput.model; else echo silent; fi)"
printf '{"route": false}\n' > "$C1GD/jev/config.json"
c1_floor "C1 row6b jev route false -> floor applies" - general-purpose sonnet
rm -rf "$C1GD/jev" "$C1HOME/.claude/skills"; rm -f "$C1R/.claude/settings.local.json"
```

Row 6 stays one assertion (was `c1_silent`), so C1's count is unchanged.

- [ ] **Step 5: Verify.**
- `run-block.sh … v4.4.0 J-MF`: 11 passed, 0 failed.
- `run-block.sh … v4.3.0 C1`: the baseline count, 0 failed.
- `run-block.sh … v4.4.0 J-DIFF`: still green, because no config means no step-aside in either copy.
- `run-block.sh … v4.4.0 J-LIB`: green.
- `bash -n` on both files, `cmp` both mirrors.
Record in `progress.md` that C1 row 6 changed by design (R-2).

- [ ] **Step 6: Commit** (`fix(hooks): model-floor steps aside only when the Jev router will run in this checkout (v4.4.0 R-2)`). Paths: `hooks/lib/agent-model.sh hooks/model-floor.sh user-level-reference/hooks/lib/agent-model.sh user-level-reference/hooks/model-floor.sh scripts/test-hooks.sh`.

---

### Task 4: `redact.py` (Phase 0 redactor, exact-cap trim) and the J-PY runner

**Files:**
- Create: `user-level-reference/skills/jev/redact.py`
- Create: `user-level-reference/skills/jev/tests/test_redact.py`
- Modify: `scripts/test-hooks.sh` (J-PY block after J-MF)
- Modify: `scripts/test-hooks-parser-matrix.sh` (`EXP_JQ_SKIP` + 4, with a calibration comment line)

**Interfaces:**
- Produces: `redact(text) -> (str, dict)`, `trim(text, cap) -> str` (len ≤ cap whenever cap ≥ 40), `residual_findings(text) -> list[str]`.
- Produces: the J-PY block with `JPY_WANT` (exact test count), which every later Python task bumps.

- [ ] **Step 1: Write the failing tests.** These are the 15 Phase 0 tests with fake tokens assembled at runtime and the trim test tightened (R-7), plus one new test.

```python
"""Tests for the Jev redactor (Phase 0's 15, trim tightened to the exact cap, + 1).

Run: python3 -B -m unittest discover -s user-level-reference/skills/jev/tests -v
Fake secrets are assembled at runtime so no token-shaped literal is committed.
"""
import getpass
import os
import sys
import unittest

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from redact import redact, residual_findings, trim  # noqa: E402

USER = getpass.getuser()


class RedactTests(unittest.TestCase):
    def assertMasked(self, text, secret, kind):
        out, counts = redact(text)
        self.assertNotIn(secret, out)
        self.assertIn("[REDACTED:" + kind + "]", out)
        self.assertGreaterEqual(counts.get(kind, 0), 1)

    def test_anthropic_and_openai_style_keys(self):
        k1 = "sk-" + "ant-api03-AbCdEf0123456789xyzXYZ"
        k2 = "sk-" + "proj-1234567890abcdefghij"
        self.assertMasked("key " + k1 + " done", k1, "api_key")
        self.assertMasked("export OPENAI=" + k2, k2, "api_key")

    def test_github_tokens(self):
        t1 = "ghp_" + "a1B2" * 9
        t2 = "github_" + "pat_11ABCDEFG0123456789_abcdefghijklmnop"
        self.assertMasked("t=" + t1, t1, "github_token")
        self.assertMasked(t2, t2, "github_token")

    def test_aws_slack_jwt(self):
        aws = "AKIA" + "ABCDEFGHIJKLMNOP"
        slack = "xox" + "b-1234567890-abcdefghijkl"
        jwt = "eyJ" + "hbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U"
        self.assertMasked(aws, aws, "aws_key")
        self.assertMasked(slack, slack, "slack_token")
        self.assertMasked("cookie " + jwt, jwt, "jwt")

    def test_bearer_header(self):
        self.assertMasked("Authorization: Bearer abcdef0123456789ABCDEF", "abcdef0123456789ABCDEF", "bearer")

    def test_pem_block(self):
        pem = "-----BEGIN RSA " + "PRIVATE KEY-----\nMIIEow\nabc\n-----END RSA " + "PRIVATE KEY-----"
        self.assertMasked("x\n" + pem + "\ny", "MIIEow", "private_key")

    def test_key_value_keeps_name_masks_value(self):
        out, counts = redact('password = "hunter2hunter2"')
        self.assertNotIn("hunter2hunter2", out)
        self.assertIn("password", out)
        self.assertGreaterEqual(counts.get("key_value", 0), 1)
        out, _ = redact("TYPESAFE_API_KEY=sk-abc")  # short value still masked via key=value
        self.assertNotIn("sk-abc", out)

    def test_url_credentials(self):
        self.assertMasked("https://bob:s3cretPass@example.com/x", "s3cretPass", "url_credentials")

    def test_email_and_user_paths(self):
        u = USER
        mail = "jane.doe" + "@" + "example.org"
        out, _ = redact("mail " + mail + " path C:\\Users\\" + u + "\\x and /c/Users/" + u + "/y and C:/Users/" + u + "/z")
        self.assertNotIn(mail, out)
        self.assertNotIn(u, out)
        self.assertIn("[REDACTED:email]", out)
        self.assertIn("~", out)

    def test_bare_username_masked(self):
        out, _ = redact("owned by " + USER + " on this box")
        self.assertNotIn(USER, out)

    def test_git_shas_and_ordinary_text_untouched(self):
        text = "commit b43b14010ee2f9c5ec2825b6f2b9d972b0250ea7 merged; tokens counted: 1250 passed"
        out, counts = redact(text)
        self.assertEqual(out, text)
        self.assertEqual(sum(counts.values()), 0)


class TrimTests(unittest.TestCase):
    def test_short_text_unchanged(self):
        self.assertEqual(trim("abc", 10), "abc")

    def test_long_text_keeps_head_and_tail(self):
        text = "H" * 3000 + "M" * 5000 + "T" * 3000
        out = trim(text, 4000)
        self.assertTrue(out.startswith("H" * 1900))
        self.assertTrue(out.endswith("T" * 1900))
        self.assertIn("[trimmed 7029 chars]", out)
        self.assertLessEqual(len(out), 4000)

    def test_trim_never_exceeds_cap(self):
        for n in (4000, 4001, 4029, 5000, 100000):
            self.assertLessEqual(len(trim("x" * n, 4000)), 4000, n)


class ResidualTests(unittest.TestCase):
    def test_flags_unknown_high_entropy_token(self):
        self.assertTrue(residual_findings("value Zq8vN2kLpX4rT7wY1mB6cF9hJ3sD5gA0eU"))

    def test_ignores_hex_hashes_and_paths(self):
        self.assertEqual(residual_findings("sha b43b14010ee2f9c5ec2825b6f2b9d972b0250ea7 and sha256 " + "a" * 64), [])
        self.assertEqual(residual_findings("see templates/general/.claude/agents/code-reviewer.md"), [])

    def test_flags_leftover_private_key_marker(self):
        self.assertTrue(residual_findings("-----BEGIN OPENSSH " + "PRIVATE KEY-----"))


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run and watch it fail.** `python3 -B -m unittest discover -s user-level-reference/skills/jev/tests -v`. Expected: `ModuleNotFoundError: No module named 'redact'`.

- [ ] **Step 3: Create `redact.py`.** Copy the spike's `G:/git/.worktrees/claude-code-toolkit/jev-phase0/spikes/jev-phase0/redact.py` verbatim: `_USER`, `_PATTERNS`, `_HEXISH`, `_TOKEN`, `redact()` and `residual_findings()`. Then make exactly two changes. First, replace the module docstring:

```python
"""Redaction, trimming and a fail-closed residual check for what the Jev router sends.

From the Jev Phase 0 spike (spikes/jev-phase0/redact.py), unchanged except trim(),
which now keeps the WHOLE result -- marker included -- within the cap (spec step 3:
"trim to 4,000 chars"; the spike's version overshot by the marker's length).

Order matters: redact the FULL text first (trimming could cut a secret in half so
no pattern matches), then trim, then run residual_findings() on what would be sent.
Any residual finding means nothing is sent -- egress is fail-closed.
"""
import sys

sys.dont_write_bytecode = True

import getpass  # noqa: E402
import re  # noqa: E402
```

Second, replace `trim()` with:

```python
def trim(text, cap):
    """Keep the head and tail of text longer than cap; the result, marker included, is at most cap chars."""
    if len(text) <= cap:
        return text
    # The marker sized for the LARGEST count it can show, so the real one is never longer.
    keep = max(cap - len("\n...[trimmed {} chars]...\n".format(len(text))), 0)
    head, tail = keep - keep // 2, keep // 2
    removed = len(text) - head - tail
    return text[:head] + "\n...[trimmed {} chars]...\n".format(removed) + (text[len(text) - tail:] if tail else "")
```

- [ ] **Step 4: Run.** Same command. Expected: `Ran 16 tests … OK`. Then `find user-level-reference/skills/jev -name __pycache__` must print nothing.

- [ ] **Step 5: Write the J-PY block** (after `# ---- end v4.4.0 J-MF`):

```bash
# ---- v4.4.0 J-PY: the Jev skill's Python tests (stdlib unittest, the system python3 the registration runs) ----
# No fourth gate command: the suite runs here, inside **Gate**. The count is
# EXACT so a test file that stops being discovered goes red, and nothing may
# skip (a skipped E2E test would hide a missing hooks/lib/agent-model.sh).
# Skipped by name (4) only where python3 is absent: the jq-only matrix config.
echo "=== user-level-reference/skills/jev (v4.4.0 J-PY) ==="
JPY_WANT=16
JPY_DIR="$ROOT/user-level-reference/skills/jev"
if command -v python3 >/dev/null 2>&1 && python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' >/dev/null 2>&1; then
  JPY_OUT=$(JEV_REPO_ROOT="$(natpath "$ROOT")" PYTHONDONTWRITEBYTECODE=1 python3 -B -m unittest discover -s "$(natpath "$JPY_DIR/tests")" -p 'test_*.py' 2>&1); JPY_RC=$?
  [ "$JPY_RC" -eq 0 ] || printf '%s\n' "$JPY_OUT" | tail -40
  expect "J-PY python tests pass"               0 "$JPY_RC"
  expect "J-PY ran exactly $JPY_WANT tests"     "$JPY_WANT" "$(printf '%s\n' "$JPY_OUT" | sed -n 's/^Ran \([0-9]*\) tests\{0,1\} in .*/\1/p')"
  expect "J-PY nothing skipped"                 0 "$(printf '%s\n' "$JPY_OUT" | grep -c 'skipped=')"
  expect "J-PY no __pycache__ in the reference" 0 "$(find "$JPY_DIR" -name __pycache__ | wc -l | tr -d ' ')"
else
  skip "J-PY python tests" "no python3 >= 3.8 on this host" 4
fi
# ---- end v4.4.0 J-PY
```

- [ ] **Step 6: Matrix constant.** In `scripts/test-hooks-parser-matrix.sh`, raise `EXP_JQ_SKIP` by exactly 4 from the value you find after the rebase (221 at v4.3.0, so 225 if v4.3.1 left it unchanged). Add one line to the calibration comment above it: `#  v4.4.0 J-PY skips 4 by name when python3 is absent (jq-only); J-DIFF, J-LIB and J-MF skip nothing in any configuration.` `EXP_PY_SKIP` and `EXP_NODE_SKIP` do not change: no new block uses `node -e`.

- [ ] **Step 7: Verify.** `run-block.sh … v4.4.0 J-PY`: 4 passed. Red side: temporarily set `JPY_WANT=15` and check that the count row FAILs, then restore it. `bash -n scripts/test-hooks.sh scripts/test-hooks-parser-matrix.sh`.

- [ ] **Step 8: Commit** (`feat(jev): redact.py with an exact 4,000-char trim; J-PY runs the skill's tests inside the Gate (v4.4.0)`). Paths: `user-level-reference/skills/jev/redact.py user-level-reference/skills/jev/tests/test_redact.py scripts/test-hooks.sh scripts/test-hooks-parser-matrix.sh`.

---

### Task 5: `jev_route.py` decision core (pure functions)

**Files:**
- Create: `user-level-reference/skills/jev/jev_route.py` (module header, constants, `family`, `decide`, `parse_answers`, `build_state`, `build_request`, `emit`)
- Create: `user-level-reference/skills/jev/tests/test_decide.py`
- Modify: `scripts/test-hooks.sh` J-PY `JPY_WANT=16` → `36`

**Interfaces:**
- Produces:
  - `family(model: str) -> str | None`: an alias for itself, `claude-<fam>-…` for its family, else None.
  - `decide(kind, default, subagent_type, answer, threshold) -> (model_or_None, applied: bool, reason: str)`.
  - `parse_answers(raw: bytes) -> (model_ans | None, effort_ans | None)`, each a dict `{"choice", "confidence": float, "probabilities": dict}`.
  - `build_state(tool_input: dict) -> (state: str, findings: list)`.
  - `build_request(state: str, jev_model: str) -> bytes`.
  - `emit(tool_input: dict, model: str) -> bytes`, b"" on failure.
  - Constants `ORDER`, `EFFORTS`, `STATE_CAP`, `SPAWN_QUESTIONS`.

- [ ] **Step 1: Write the failing tests** (`tests/test_decide.py`):

```python
"""jev_route decision core: bounds, threshold, role floor, request and output shape (v4.4.0 Task 5)."""
import json
import os
import sys
import unittest

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import jev_route as jr  # noqa: E402


def ans(choice, conf):
    return {"choice": choice, "confidence": conf, "probabilities": {}}


# Every value class an emitter could mangle (C1's C1TI, as a Python dict).
C1TI = {"subagent_type": "general-purpose", "prompt": "deep", "description": "d", "zz_unknown": 1,
        "nested": {"a": [1, 2, {"b": None}], "t": True, "f": False, "e": {}, "l": []},
        "__proto__": {"x": 1}, "u": "a b\u00e9\u2028", "tab": "x\ty"}


class DecideTests(unittest.TestCase):
    def test_floor_one_step_up_applies(self):
        self.assertEqual(jr.decide("floor", "sonnet", "general-purpose", ans("opus", 0.9), 0.8), ("opus", True, "applied"))

    def test_own_one_step_down_applies(self):
        self.assertEqual(jr.decide("own", "opus", "coder", ans("sonnet", 0.85), 0.8), ("sonnet", True, "applied"))

    def test_threshold_is_inclusive(self):
        self.assertEqual(jr.decide("floor", "sonnet", "Plan", ans("haiku", 0.8), 0.8), ("haiku", True, "applied"))

    def test_below_threshold_floor_emits_floor_own_emits_nothing(self):
        self.assertEqual(jr.decide("floor", "sonnet", "Plan", ans("haiku", 0.79), 0.8), ("sonnet", False, "low-confidence"))
        self.assertEqual(jr.decide("own", "opus", "coder", ans("sonnet", 0.79), 0.8), (None, False, "low-confidence"))

    def test_two_step_move_refused(self):
        self.assertEqual(jr.decide("floor", "haiku", "Explore", ans("opus", 0.99), 0.8), ("haiku", False, "out-of-bounds"))
        self.assertEqual(jr.decide("own", "fable", "architect", ans("sonnet", 0.99), 0.8), (None, False, "out-of-bounds"))

    def test_reviewer_never_below_sonnet(self):
        self.assertEqual(jr.decide("own", "sonnet", "code-reviewer", ans("haiku", 0.99), 0.8), (None, False, "role-floor"))
        self.assertEqual(jr.decide("floor", "sonnet", "my-Architect", ans("haiku", 0.99), 0.8), ("sonnet", False, "role-floor"))

    def test_role_floor_limits_the_choice_not_the_default(self):
        # A reviewer whose own model is haiku keeps it; Jev may raise it, never lower it.
        self.assertEqual(jr.decide("own", "haiku", "code-reviewer", ans("haiku", 0.99), 0.8), (None, False, "kept"))
        self.assertEqual(jr.decide("own", "haiku", "code-reviewer", ans("sonnet", 0.99), 0.8), ("sonnet", True, "applied"))

    def test_same_choice_kept(self):
        self.assertEqual(jr.decide("floor", "sonnet", "general-purpose", ans("sonnet", 0.99), 0.8), ("sonnet", False, "kept"))
        self.assertEqual(jr.decide("own", "opus", "coder", ans("opus", 0.99), 0.8), (None, False, "kept"))

    def test_full_id_maps_to_its_family(self):
        self.assertEqual(jr.family("claude-opus-4-1"), "opus")
        self.assertEqual(jr.decide("own", "claude-opus-4-1", "x", ans("sonnet", 0.9), 0.8), ("sonnet", True, "applied"))
        self.assertEqual(jr.decide("own", "claude-opus-4-1", "x", ans("opus", 0.9), 0.8), (None, False, "kept"))

    def test_unmappable_default_is_pinned(self):
        self.assertEqual(jr.decide("own", "gpt-5", "x", ans("sonnet", 0.99), 0.8), (None, False, "pinned"))

    def test_no_answer_is_bad_response(self):
        self.assertEqual(jr.decide("floor", "sonnet", "Plan", None, 0.8), ("sonnet", False, "bad-response"))
        self.assertEqual(jr.decide("own", "opus", "coder", None, 0.8), (None, False, "bad-response"))


class PayloadTests(unittest.TestCase):
    def test_state_is_type_description_prompt(self):
        state, findings = jr.build_state({"subagent_type": "coder", "description": "fix it", "prompt": "Do X."})
        self.assertEqual(state, "agent_type: coder\ndescription: fix it\n\nDo X.")
        self.assertEqual(findings, [])

    def test_state_untyped_reads_general_purpose(self):
        state, _ = jr.build_state({"prompt": "p"})
        self.assertTrue(state.startswith("agent_type: general-purpose\n"))

    def test_state_redacted_then_capped_at_4000(self):
        mail = "jane.doe" + "@" + "example.org"
        state, findings = jr.build_state({"subagent_type": "coder", "description": "d", "prompt": mail + " " + "word " * 3000})
        self.assertNotIn(mail, state)
        self.assertLessEqual(len(state), 4000)
        self.assertEqual(findings, [])

    def test_residual_secret_reported(self):
        _, findings = jr.build_state({"prompt": "value Zq8vN2kLpX4rT7wY1mB6cF9hJ3sD5gA0eU"})
        self.assertTrue(findings)

    def test_request_pins_model_and_phase0_questions(self):
        body = json.loads(jr.build_request("S", "jev-1.13.0").decode("utf-8"))
        self.assertEqual((body["state"], body["model"]), ("S", "jev-1.13.0"))
        self.assertEqual(sorted(body["questions"]), ["effort", "model"])
        self.assertEqual(sorted(body["questions"]["model"]["criteria"]), ["fable", "haiku", "opus", "sonnet"])
        self.assertEqual(sorted(body["questions"]["effort"]["criteria"]), ["high", "low", "medium", "xhigh"])
        self.assertEqual(body["questions"]["model"]["instructions"],
                         "Which Claude model is the least costly one that can complete this delegated task correctly on the first attempt?")

    def test_parse_answers_ok(self):
        raw = json.dumps({"answers": {
            "model": {"type": "choice", "choice": "opus", "confidence": 0.91, "probabilities": {"opus": 0.91, "sonnet": 0.09}},
            "effort": {"type": "choice", "choice": "high", "confidence": 0.6, "probabilities": {}}}}).encode("utf-8")
        m, e = jr.parse_answers(raw)
        self.assertEqual((m["choice"], m["confidence"], m["probabilities"]), ("opus", 0.91, {"opus": 0.91, "sonnet": 0.09}))
        self.assertEqual((e["choice"], e["confidence"]), ("high", 0.6))

    def test_parse_answers_rejects_bad_shapes(self):
        for raw in (b"not json", b"[]", b'{"answers": 1}',
                    b'{"answers": {"model": {"choice": "gpt", "confidence": 0.9}}}',
                    b'{"answers": {"model": {"choice": "opus", "confidence": true}}}',
                    b'{"answers": {"model": {"choice": "opus", "confidence": 1.5}}}',
                    b'{"answers": {"model": {"choice": "opus", "confidence": NaN}}}'):
            self.assertIsNone(jr.parse_answers(raw)[0], raw)

    def test_emit_copies_whole_tool_input_and_sets_model(self):
        out = json.loads(jr.emit(dict(C1TI), "opus").decode("utf-8"))
        self.assertEqual(sorted(out), ["hookSpecificOutput"])
        hso = out["hookSpecificOutput"]
        self.assertEqual(sorted(hso), ["hookEventName", "updatedInput"])  # never a permissionDecision
        self.assertEqual(hso["hookEventName"], "PreToolUse")
        ui = dict(hso["updatedInput"])
        self.assertEqual(ui.pop("model"), "opus")
        self.assertEqual(ui, C1TI)

    def test_emit_refuses_non_json_numbers(self):
        self.assertEqual(jr.emit({"prompt": "p", "n": float("inf")}, "sonnet"), b"")


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run and watch it fail.** `python3 -B -m unittest discover -s user-level-reference/skills/jev/tests -v`. Expected: `ModuleNotFoundError: No module named 'jev_route'`.

- [ ] **Step 3: Create `jev_route.py`** with the full import list now (later tasks append functions only):

```python
#!/usr/bin/env python3
"""jev_route.py -- PreToolUse(Agent) router for the optional Jev layer (toolkit v4.4.0).

Spec: docs/plans/2026-09-28-jev-phase1-design.md (Phase 1a); plan:
docs/plans/2026-10-02-jev-phase1-implementation.md (rulings R-1..R-9).
Registered only by `/jev on`, as ONE entry in one checkout's
.claude/settings.local.json:
    f="$HOME/.claude/skills/jev/jev_route.py"; [ -f "$f" ] && python3 "$f"; exit 0

Contract:
- STDOUT is exactly one {"hookSpecificOutput": {"hookEventName": "PreToolUse",
  "updatedInput": {...}}} object, or nothing. Never a permissionDecision: a
  router must never auto-approve a spawn (ruling S-19).
- An explicit `model` in the call is never changed. A typed agent moves at most
  one step from its own model; review/architect types never below sonnet.
- A floor-class spawn (built-in, `model: inherit`, no model) ALWAYS leaves with
  a model -- Jev's choice when every check passes, else the project floor --
  because model-floor.sh has stepped aside for this checkout (R-1).
- Exit 0 always. The state text and the key are never logged.
"""
import sys

sys.dont_write_bytecode = True  # no __pycache__ beside the installed skill (drift)

import datetime  # noqa: E402
import json  # noqa: E402
import os  # noqa: E402
import re  # noqa: E402
import shutil  # noqa: E402
import socket  # noqa: E402
import subprocess  # noqa: E402
import threading  # noqa: E402
import time  # noqa: E402
import urllib.error  # noqa: E402
import urllib.parse  # noqa: E402
import urllib.request  # noqa: E402
from typing import NamedTuple  # noqa: E402

from redact import redact, residual_findings, trim  # noqa: E402

JEV_MODEL_DEFAULT = "jev-1.13.0"
THRESHOLD_DEFAULT = 0.8
ENDPOINT = "https://api.typesafe.ai/v1/systemone"
STATE_CAP = 4000
HTTP_TIMEOUT = 2.0
DEADLINE = 3.5  # seconds after start; the registration's hook timeout is 5
RESOLVER_TIMEOUT = 2.0
MAX_RESPONSE = 65536
ORDER = ("haiku", "sonnet", "opus", "fable")
EFFORTS = ("low", "medium", "high", "xhigh")
ROLE_FLOOR_RE = re.compile(r"review|architect", re.I)
FAMILY_RE = re.compile(r"^claude-(haiku|sonnet|opus|fable)-")

# The Phase 0 questions, verbatim (spikes/jev-phase0/extract_payloads.py): the
# measured agreement (model 98.5 %, effort 97.1 % within one step) holds for
# THIS wording against jev-1.13.0 only.
SPAWN_QUESTIONS = {
    "model": {
        "type": "choice",
        "instructions": "Which Claude model is the least costly one that can complete this delegated task correctly on the first attempt?",
        "criteria": {
            "haiku": "Read-only search, lookups, listing or simple extraction; no judgement and no edits.",
            "sonnet": "Well-specified implementation, tests, fixes or mechanical multi-file edits that follow a clear brief.",
            "opus": "Code review, debugging with an unclear root cause, design judgement, security-sensitive or cross-cutting changes.",
            "fable": "Architecture across subsystems, ambiguous high-stakes decisions, or very long multi-step reasoning.",
        },
    },
    "effort": {
        "type": "choice",
        "instructions": "How much reasoning effort does this delegated task need to avoid skipped files or steps?",
        "criteria": {
            "low": "A single lookup or a mechanical change with nothing to weigh.",
            "medium": "A clear brief with a few steps and ordinary verification.",
            "high": "Many steps or files, edge cases to track, verification that is easy to skip.",
            "xhigh": "Adversarial review, subtle correctness or security reasoning, or a large surface to check exhaustively.",
        },
    },
}


def family(model):
    """The alias family of a model: an alias itself, claude-<fam>-... -> <fam>, else None."""
    if model in ORDER:
        return model
    m = FAMILY_RE.match(model or "")
    return m.group(1) if m else None


def decide(kind, default, subagent_type, answer, threshold):
    """Bound Jev's answer (spec step 6). -> (model to emit or None, applied, reason).

    A floor spawn always gets a model (R-1): the floor itself when Jev's choice
    is not applied. A typed spawn gets one only for an applied move.
    """
    fallback = default if kind == "floor" else None
    fam = family(default)
    if fam is None:
        return fallback, False, "pinned"
    if not answer:
        return fallback, False, "bad-response"
    choice, conf = answer["choice"], answer["confidence"]
    if conf < threshold:
        return fallback, False, "low-confidence"
    if abs(ORDER.index(choice) - ORDER.index(fam)) > 1:
        return fallback, False, "out-of-bounds"
    if choice == fam:
        return fallback, False, "kept"
    if ROLE_FLOOR_RE.search(subagent_type or "") and ORDER.index(choice) < ORDER.index("sonnet"):
        return fallback, False, "role-floor"
    return choice, True, "applied"


def _answer(answers, key, choices):
    a = answers.get(key) if isinstance(answers, dict) else None
    if not isinstance(a, dict):
        return None
    choice, conf = a.get("choice"), a.get("confidence")
    if choice not in choices or isinstance(conf, bool) or not isinstance(conf, (int, float)):
        return None
    if not 0.0 <= conf <= 1.0:  # also false for NaN
        return None
    probs = a.get("probabilities") if isinstance(a.get("probabilities"), dict) else {}
    probs = {k: v for k, v in probs.items()
             if k in choices and isinstance(v, (int, float)) and not isinstance(v, bool)}
    return {"choice": choice, "confidence": float(conf), "probabilities": probs}


def parse_answers(raw):
    """-> (model answer or None, effort answer or None) from a /v1/systemone body."""
    try:
        obj = json.loads(raw.decode("utf-8"))
    except (AttributeError, UnicodeDecodeError, ValueError):
        return None, None
    answers = obj.get("answers") if isinstance(obj, dict) else None
    return _answer(answers, "model", ORDER), _answer(answers, "effort", EFFORTS)


def build_state(tool_input):
    """Spec step 3: type + description + prompt, redacted, then trimmed. -> (state, residual findings)."""
    text = "agent_type: {}\ndescription: {}\n\n{}".format(
        tool_input.get("subagent_type") or "general-purpose",
        tool_input.get("description") or "",
        tool_input.get("prompt") or "")
    redacted, _counts = redact(text)
    state = trim(redacted, STATE_CAP)
    return state, residual_findings(state)


def build_request(state, jev_model):
    return json.dumps({"state": state, "model": jev_model, "questions": SPAWN_QUESTIONS},
                      ensure_ascii=False).encode("utf-8")


def emit(tool_input, model):
    """The hook's stdout: the WHOLE original tool_input with only `model` set
    (updatedInput REPLACES it). b"" when it cannot be written as strict JSON."""
    try:
        ti = dict(tool_input)
        ti["model"] = model
        out = json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "updatedInput": ti}},
                         ensure_ascii=False, allow_nan=False)
    except (TypeError, ValueError):
        return b""
    return out.encode("utf-8")
```

- [ ] **Step 4: Run.** Expected: `Ran 36 tests … OK`.

- [ ] **Step 5: Bump J-PY** `JPY_WANT=36`. Run `run-block.sh … v4.4.0 J-PY`: 4 passed.

- [ ] **Step 6: Commit** (`feat(jev): router decision core -- one-step bound, reviewer floor, threshold, strict updatedInput (v4.4.0)`). Paths: `user-level-reference/skills/jev/jev_route.py user-level-reference/skills/jev/tests/test_decide.py scripts/test-hooks.sh`.

---

### Task 6: `jev_route.run()`: keys, endpoint, config, events, and the floor fallback

**Files:**
- Modify: `user-level-reference/skills/jev/jev_route.py` (append after `emit`)
- Create: `user-level-reference/skills/jev/tests/test_route.py`
- Modify: `scripts/test-hooks.sh`, J-PY `JPY_WANT=36` → `63`

**Interfaces:**
- Consumes: Task 5's functions.
- Produces:
  - `Resolution(kind, model, jev, effort, gd)` (NamedTuple);
  - `REASONS` (frozenset) and `EVENT_FIELDS` (tuple);
  - exceptions `JevTimeout`, `HttpError`;
  - `load_key(env, registry=None) -> str`, `pick_endpoint(env) -> str | None`, `read_config(gd) -> (jev_model, threshold)`;
  - `write_event(gd, ev, now=None)`;
  - `run(stdin_bytes, env, resolver=None, post=None, registry=None, clock=time.monotonic) -> (stdout_bytes, event | None, gd)`.
  - Contracts on the injected callables: `resolver(subagent_type: str, cwd: str, env: dict) -> Resolution | None`; `post(url, body: bytes, key, timeout: float, env) -> bytes`, which raises `JevTimeout` or `HttpError`/`OSError`. Task 7 supplies the real `run_resolver` and `post_with_deadline` under these names.

- [ ] **Step 1: Write the failing tests** (`tests/test_route.py`):

```python
"""jev_route.run(): the hook's whole decision with fake resolver and transport (v4.4.0 Task 6).

No test here touches the network or the registry: `post` and `registry` are
injected, and JEV_TEST_MODE=1 is set wherever env reaches load_key/pick_endpoint.
"""
import itertools
import json
import os
import shutil
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import jev_route as jr  # noqa: E402

KEY = "fake-key-0123456789"
MARK = "PROMPT-MARKER-7391"
ENV = {"JEV_TEST_MODE": "1", "JEV_ENDPOINT": "http://127.0.0.1:9/v1/systemone", "TYPESAFE_API_KEY": KEY}


def payload(stype="general-purpose", model=None, tool="Agent", extra=None):
    ti = {"prompt": "Summarise the README. " + MARK, "description": "d", "zz": 1}
    if stype is not None:
        ti["subagent_type"] = stype
    if model is not None:
        ti["model"] = model
    ti.update(extra or {})
    return json.dumps({"tool_name": tool, "tool_input": ti, "cwd": "."}).encode("utf-8")


def answer(choice, conf, effort="medium"):
    return json.dumps({"answers": {
        "model": {"choice": choice, "confidence": conf, "probabilities": {choice: conf}},
        "effort": {"choice": effort, "confidence": 0.7, "probabilities": {}}}}).encode("utf-8")


class Recorder:
    """A fake `post`: records each call, returns `result` or raises `exc`."""
    def __init__(self, result=None, exc=None):
        self.calls, self.result, self.exc = [], result, exc

    def __call__(self, url, body, key, timeout, env):
        self.calls.append({"url": url, "body": body, "key": key, "timeout": timeout})
        if self.exc is not None:
            raise self.exc
        return self.result


class RunTests(unittest.TestCase):
    def setUp(self):
        self.gd = tempfile.mkdtemp(prefix="jev-gd-")
        self.addCleanup(shutil.rmtree, self.gd, True)

    def res(self, kind="floor", model="sonnet", jev=True, effort=""):
        r = jr.Resolution(kind, model, jev, effort, self.gd)
        return lambda t, c, e: r

    def go(self, data, resolver=None, post=None, env=ENV, clock=None):
        kw = {"resolver": resolver or self.res(), "post": post or Recorder(answer("opus", 0.95)),
              "registry": lambda: ""}
        if clock is not None:
            kw["clock"] = clock
        return jr.run(data, dict(env), **kw)

    @staticmethod
    def model_of(out):
        return json.loads(out.decode("utf-8"))["hookSpecificOutput"]["updatedInput"]["model"] if out else None

    def test_off_means_no_output_no_event_no_network(self):
        post = Recorder(answer("opus", 0.99))
        out, ev, _ = self.go(payload(), resolver=self.res(jev=False), post=post)
        self.assertEqual((out, ev, post.calls), (b"", None, []))

    def test_resolver_unavailable_is_off(self):
        post = Recorder(answer("opus", 0.99))
        out, ev, _ = self.go(payload(), resolver=lambda t, c, e: None, post=post)
        self.assertEqual((out, ev, post.calls), (b"", None, []))

    def test_not_agent_or_invalid_payload_silent(self):
        for data in (payload(tool="Bash"), b"not json", b"",
                     json.dumps({"tool_name": "Agent", "tool_input": "s"}).encode("utf-8")):
            out, ev, _ = self.go(data)
            self.assertEqual((out, ev), (b"", None), data)

    def test_explicit_model_untouched_and_logged(self):
        post = Recorder(answer("haiku", 0.99))
        out, ev, _ = self.go(payload(model="opus"), post=post)
        self.assertEqual((out, ev["reason"], post.calls), (b"", "explicit", []))

    def test_env_and_none_kinds_untouched_and_logged(self):
        for kind in ("env", "none"):
            post = Recorder(answer("haiku", 0.99))
            out, ev, _ = self.go(payload(), resolver=self.res(kind=kind, model=""), post=post)
            self.assertEqual((out, ev["reason"], post.calls), (b"", kind, []))

    def test_floor_spawn_routed_within_bounds(self):
        out, ev, _ = self.go(payload(), post=Recorder(answer("opus", 0.95)))
        self.assertEqual(self.model_of(out), "opus")
        self.assertEqual((ev["applied"], ev["reason"], ev["default"], ev["choice"], ev["emitted"]),
                         (True, "applied", "sonnet", "opus", "opus"))

    def test_typed_spawn_routed_and_input_preserved(self):
        out, _, _ = self.go(payload("coder"), resolver=self.res(kind="own", model="opus"),
                            post=Recorder(answer("sonnet", 0.9)))
        ui = json.loads(out.decode("utf-8"))["hookSpecificOutput"]["updatedInput"]
        self.assertEqual((ui["model"], ui["subagent_type"], ui["zz"], ui["description"]), ("sonnet", "coder", 1, "d"))
        self.assertTrue(ui["prompt"].endswith(MARK))  # the ORIGINAL prompt, not the redacted state

    def test_typed_spawn_low_confidence_silent(self):
        out, ev, _ = self.go(payload("coder"), resolver=self.res(kind="own", model="opus"),
                             post=Recorder(answer("sonnet", 0.5)))
        self.assertEqual((out, ev["reason"], ev["applied"]), (b"", "low-confidence", False))

    def test_floor_spawn_low_confidence_gets_floor(self):
        out, ev, _ = self.go(payload("Plan"), post=Recorder(answer("haiku", 0.5)))
        self.assertEqual((self.model_of(out), ev["reason"]), ("sonnet", "low-confidence"))

    def test_no_key_floor_gets_floor_without_a_call(self):
        env = dict(ENV)
        del env["TYPESAFE_API_KEY"]
        post = Recorder(answer("opus", 0.99))
        out, ev, _ = self.go(payload(), post=post, env=env)
        self.assertEqual((self.model_of(out), ev["reason"], post.calls), ("sonnet", "no-key", []))

    def test_no_key_typed_silent(self):
        env = dict(ENV)
        del env["TYPESAFE_API_KEY"]
        out, ev, _ = self.go(payload("coder"), resolver=self.res(kind="own", model="opus"), env=env)
        self.assertEqual((out, ev["reason"]), (b"", "no-key"))

    def test_no_endpoint_in_test_mode_means_no_call(self):
        env = dict(ENV, JEV_ENDPOINT="https://api.typesafe.ai/v1/systemone")
        post = Recorder(answer("opus", 0.99))
        out, ev, _ = self.go(payload(), post=post, env=env)
        self.assertEqual((self.model_of(out), ev["reason"], post.calls), ("sonnet", "no-endpoint", []))

    def test_residual_secret_means_no_call(self):
        post = Recorder(answer("opus", 0.99))
        out, ev, _ = self.go(payload(extra={"prompt": "use Zq8vN2kLpX4rT7wY1mB6cF9hJ3sD5gA0eU"}), post=post)
        self.assertEqual((self.model_of(out), ev["reason"], post.calls), ("sonnet", "egress-refused", []))

    def test_transport_failures_fall_back(self):
        for exc, reason in ((jr.JevTimeout(), "timeout"), (jr.HttpError("500"), "http-error"),
                            (OSError("refused"), "http-error")):
            out, ev, _ = self.go(payload(), post=Recorder(exc=exc))
            self.assertEqual((self.model_of(out), ev["reason"]), ("sonnet", reason))

    def test_garbage_response_falls_back(self):
        out, ev, _ = self.go(payload(), post=Recorder(b"<html>"))
        self.assertEqual((self.model_of(out), ev["reason"]), ("sonnet", "bad-response"))

    def test_unexpected_exception_still_floors(self):
        out, ev, _ = self.go(payload(), post=Recorder(exc=RuntimeError("bug")))
        self.assertEqual((self.model_of(out), ev["reason"]), ("sonnet", "error"))

    def test_deadline_spent_means_no_call(self):
        ticks = itertools.chain([0.0, 3.49], itertools.repeat(3.6))
        post = Recorder(answer("opus", 0.99))
        out, ev, _ = self.go(payload(), post=post, clock=lambda: next(ticks))
        self.assertEqual((self.model_of(out), ev["reason"], post.calls), ("sonnet", "deadline", []))

    def test_request_carries_key_pinned_model_and_capped_state(self):
        post = Recorder(answer("opus", 0.95))
        self.go(payload(extra={"prompt": "x " * 5000}), post=post)
        call = post.calls[0]
        body = json.loads(call["body"].decode("utf-8"))
        self.assertEqual((call["key"], call["url"], body["model"]), (KEY, ENV["JEV_ENDPOINT"], "jev-1.13.0"))
        self.assertLessEqual(len(body["state"]), 4000)
        self.assertLessEqual(call["timeout"], 2.0)

    def test_config_threshold_and_model_are_read(self):
        os.makedirs(os.path.join(self.gd, "jev"))
        with open(os.path.join(self.gd, "jev", "config.json"), "w", encoding="utf-8") as fh:
            json.dump({"model": "jev-1.14.0", "threshold": 0.95, "route": True}, fh)
        post = Recorder(answer("opus", 0.9))
        out, ev, _ = self.go(payload(), post=post)
        self.assertEqual(json.loads(post.calls[0]["body"].decode("utf-8"))["model"], "jev-1.14.0")
        self.assertEqual((self.model_of(out), ev["reason"]), ("sonnet", "low-confidence"))

    def test_bad_config_uses_defaults(self):
        os.makedirs(os.path.join(self.gd, "jev"))
        with open(os.path.join(self.gd, "jev", "config.json"), "w", encoding="utf-8") as fh:
            fh.write('{"route": true, "threshold": 0.01, "model": "evil"')  # truncated JSON
        post = Recorder(answer("opus", 0.85))
        out, _, _ = self.go(payload(), post=post)
        self.assertEqual(json.loads(post.calls[0]["body"].decode("utf-8"))["model"], "jev-1.13.0")
        self.assertEqual(self.model_of(out), "opus")

    def test_event_never_holds_prompt_or_key_and_reason_is_enum(self):
        for post in (Recorder(answer("opus", 0.95)), Recorder(exc=RuntimeError(MARK + KEY)),
                     Recorder(("garbage " + MARK).encode("utf-8"))):
            _, ev, _ = self.go(payload(), post=post)
            blob = json.dumps(ev)
            self.assertNotIn(MARK, blob)
            self.assertNotIn(KEY, blob)
            self.assertIn(ev["reason"], jr.REASONS)
            self.assertEqual(sorted(ev), sorted(jr.EVENT_FIELDS))

    def test_write_event_file_name_is_ntfs_safe(self):
        jr.write_event(self.gd, {"reason": "kept"})
        names = os.listdir(os.path.join(self.gd, "jev", "events"))
        self.assertEqual(len(names), 1)
        self.assertRegex(names[0], r"^\d{8}T\d{12}Z-\d+\.json$")


class KeyEndpointTests(unittest.TestCase):
    def test_env_key_wins(self):
        self.assertEqual(jr.load_key({"TYPESAFE_API_KEY": " k1 "}, registry=lambda: "k2"), "k1")

    def test_registry_fallback_outside_test_mode(self):
        self.assertEqual(jr.load_key({}, registry=lambda: " k2 "), "k2")

    def test_test_mode_never_reads_the_registry(self):
        def boom():
            raise AssertionError("registry read in test mode")
        self.assertEqual(jr.load_key({"JEV_TEST_MODE": "1"}, registry=boom), "")

    def test_production_endpoint_ignores_overrides(self):
        self.assertEqual(jr.pick_endpoint({"JEV_ENDPOINT": "http://127.0.0.1:1/x"}), jr.ENDPOINT)

    def test_test_mode_endpoint_is_loopback_only(self):
        for url in (jr.ENDPOINT, "http://example.com/x", "http://localhost:1/x", "https://127.0.0.1:1/x", ""):
            self.assertIsNone(jr.pick_endpoint({"JEV_TEST_MODE": "1", "JEV_ENDPOINT": url}), url)
        ok = "http://127.0.0.1:5/v1/systemone"
        self.assertEqual(jr.pick_endpoint({"JEV_TEST_MODE": "1", "JEV_ENDPOINT": ok}), ok)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run and watch it fail.** Expected: `AttributeError: module 'jev_route' has no attribute 'Resolution'` (and others).

- [ ] **Step 3: Append to `jev_route.py`** (after `emit`):

```python
REASONS = frozenset({
    "explicit", "env", "none", "pinned", "egress-refused", "no-key", "no-endpoint",
    "deadline", "timeout", "http-error", "bad-response", "low-confidence",
    "out-of-bounds", "role-floor", "kept", "applied", "error",
})
EVENT_FIELDS = ("ts", "subagent_type", "kind", "default", "agent_effort", "choice", "confidence",
                "probabilities", "effort_choice", "effort_confidence", "applied", "reason",
                "emitted", "latency_s")


class Resolution(NamedTuple):
    """One line of `bash hooks/lib/agent-model.sh <type> <cwd>`."""
    kind: str    # own | floor | env | none
    model: str   # "" for env/none
    jev: bool    # model-floor stepped aside: this router owns the spawn
    effort: str  # the agent file's `effort:`, "" when unset
    gd: str      # absolute git common dir, "" when unknown


class JevTimeout(Exception):
    """No answer within the deadline."""


class HttpError(Exception):
    """A non-200 status or a transport failure."""


def _winreg_key():
    if sys.platform != "win32":
        return ""
    try:
        import winreg
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment") as k:
            val, _ = winreg.QueryValueEx(k, "TYPESAFE_API_KEY")
            return str(val)
    except OSError:
        return ""


def load_key(env, registry=None):
    """TYPESAFE_API_KEY from env, else HKCU\\Environment. Test mode never reads the registry."""
    key = (env.get("TYPESAFE_API_KEY") or "").strip()
    if key or env.get("JEV_TEST_MODE") == "1":
        return key
    return ((registry or _winreg_key)() or "").strip()


def pick_endpoint(env):
    """The real endpoint, always -- except in test mode, which may only reach http://127.0.0.1."""
    if env.get("JEV_TEST_MODE") != "1":
        return ENDPOINT
    url = env.get("JEV_ENDPOINT") or ""
    parts = urllib.parse.urlsplit(url)
    if parts.scheme == "http" and parts.hostname == "127.0.0.1":
        return url
    return None


def read_config(gd):
    """-> (jev model, threshold) from <gd>/jev/config.json; defaults for anything unreadable."""
    model, threshold = JEV_MODEL_DEFAULT, THRESHOLD_DEFAULT
    try:
        with open(os.path.join(gd, "jev", "config.json"), "rb") as fh:
            cfg = json.loads(fh.read().decode("utf-8-sig"))
    except (OSError, UnicodeDecodeError, ValueError):
        return model, threshold
    if isinstance(cfg, dict):
        if isinstance(cfg.get("model"), str) and re.fullmatch(r"jev-[0-9]+(\.[0-9]+)*", cfg["model"]):
            model = cfg["model"]
        t = cfg.get("threshold")
        if isinstance(t, (int, float)) and not isinstance(t, bool) and 0.5 <= t <= 1.0:
            threshold = float(t)
    return model, threshold


def _now_utc():
    return datetime.datetime.now(datetime.timezone.utc)


def write_event(gd, ev, now=None):
    """<gd>/jev/events/<YYYYmmddTHHMMSSffffffZ>-<pid>.json -- no colon (NTFS)."""
    now = now or _now_utc()
    d = os.path.join(gd, "jev", "events")
    os.makedirs(d, exist_ok=True)
    name = "{}-{}.json".format(now.strftime("%Y%m%dT%H%M%S%fZ"), os.getpid())
    with open(os.path.join(d, name), "w", encoding="utf-8", newline="\n") as fh:
        json.dump(ev, fh, sort_keys=True, ensure_ascii=False)
        fh.write("\n")


def _new_event(stype, res):
    return {"ts": _now_utc().isoformat(timespec="milliseconds").replace("+00:00", "Z"),
            "subagent_type": stype or "general-purpose", "kind": res.kind, "default": res.model,
            "agent_effort": res.effort, "choice": None, "confidence": None, "probabilities": {},
            "effort_choice": None, "effort_confidence": None, "applied": False, "reason": "error",
            "emitted": None, "latency_s": None}


def _ask(ti, stype, res, env, post, registry, clock, t0, ev):
    """Ask Jev and bound the answer. -> (model to emit or None, reason, applied)."""
    fallback = res.model if res.kind == "floor" else None
    if family(res.model) is None:
        return fallback, "pinned", False
    state, findings = build_state(ti)
    if findings:
        return fallback, "egress-refused", False
    key = load_key(env, registry)
    if not key:
        return fallback, "no-key", False
    url = pick_endpoint(env)
    if not url:
        return fallback, "no-endpoint", False
    jev_model, threshold = read_config(res.gd)
    budget = min(HTTP_TIMEOUT, DEADLINE - (clock() - t0))
    if budget <= 0.05:
        return fallback, "deadline", False
    try:
        raw = post(url, build_request(state, jev_model), key, budget, env)
    except JevTimeout:
        return fallback, "timeout", False
    except (HttpError, OSError):
        return fallback, "http-error", False
    model_ans, effort_ans = parse_answers(raw)
    if effort_ans:
        ev["effort_choice"], ev["effort_confidence"] = effort_ans["choice"], effort_ans["confidence"]
    if model_ans:
        ev["choice"], ev["confidence"] = model_ans["choice"], model_ans["confidence"]
        ev["probabilities"] = model_ans["probabilities"]
    model, applied, reason = decide(res.kind, res.model, stype, model_ans, threshold)
    return model, reason, applied


def run(stdin_bytes, env, resolver=None, post=None, registry=None, clock=time.monotonic):
    """The whole hook minus process I/O. -> (stdout bytes, event or None, git common dir).

    An event of None means Jev is off for this checkout (the resolver says
    model-floor did not step aside, or there is no resolver): no output, no
    file, no network -- the zero-footprint path.
    """
    t0 = clock()
    try:
        payload = json.loads(stdin_bytes.decode("utf-8-sig"))
    except (UnicodeDecodeError, ValueError):
        return b"", None, ""
    if not isinstance(payload, dict) or payload.get("tool_name") != "Agent":
        return b"", None, ""
    ti = payload.get("tool_input")
    if not isinstance(ti, dict):
        return b"", None, ""
    stype = ti.get("subagent_type") if isinstance(ti.get("subagent_type"), str) else ""
    cwd = payload.get("cwd") if isinstance(payload.get("cwd"), str) and payload.get("cwd") else "."
    res = (resolver or run_resolver)(stype, cwd, env)
    if res is None or not res.jev or not res.gd:
        return b"", None, ""
    ev = _new_event(stype, res)
    fallback = res.model if res.kind == "floor" else None
    try:
        if ti.get("model"):
            model, ev["reason"] = None, "explicit"
        elif res.kind not in ("own", "floor"):
            model, ev["reason"] = None, res.kind if res.kind in REASONS else "none"
        else:
            model, ev["reason"], ev["applied"] = _ask(
                ti, stype, res, env, post or post_with_deadline, registry, clock, t0, ev)
    except Exception:  # noqa: BLE001 -- the router must never fail a spawn
        model, ev["reason"], ev["applied"] = fallback, "error", False
    out = emit(ti, model) if model else b""
    ev["emitted"] = model if out else None
    ev["latency_s"] = round(clock() - t0, 3)
    return out, ev, res.gd
```

(`run_resolver` and `post_with_deadline` arrive in Task 7. Every Task 6 test injects both, so the names are never looked up yet.)

- [ ] **Step 4: Run.** Expected: `Ran 63 tests … OK`.

- [ ] **Step 5: Bump J-PY** `JPY_WANT=63`. `run-block.sh … v4.4.0 J-PY`: 4 passed.

- [ ] **Step 6: Commit** (`feat(jev): router run() -- floor fallback on every failure, loopback-only test mode, key never logged (v4.4.0)`). Paths: `user-level-reference/skills/jev/jev_route.py user-level-reference/skills/jev/tests/test_route.py scripts/test-hooks.sh`.

---

### Task 7: Transport, resolver and `main()`, end to end against a loopback stub

**Files:**
- Modify: `user-level-reference/skills/jev/jev_route.py` (append `post_with_deadline`, `run_resolver`, `main`, `__main__`)
- Create: `user-level-reference/skills/jev/tests/jevtest.py` (shared fixtures; not a `test_*.py`, so discovery imports it but runs nothing from it)
- Create: `user-level-reference/skills/jev/tests/test_e2e.py`
- Modify: `scripts/test-hooks.sh`, J-PY `JPY_WANT=63` → `76`

**Interfaces:**
- Consumes: `Resolution`, `JevTimeout`, `HttpError`, `run()` from Task 6; the lib CLI line from Tasks 2-3.
- Produces:
  - `post_with_deadline(url, body, key, timeout, env) -> bytes`;
  - `run_resolver(subagent_type, cwd, env) -> Resolution | None` (project lib via `CLAUDE_PROJECT_DIR`, else `$HOME/.claude/hooks/lib/agent-model.sh`);
  - `main() -> int`;
  - `jevtest.Sandbox`, `jevtest.Stub`, `jevtest.run_hook`, `jevtest.agent_payload`, `jevtest.ok_answer`, `jevtest.KEY`, `jevtest.MARK`, `jevtest.LIB`, `jevtest.ROUTE`. Task 8 reuses `Sandbox`.

- [ ] **Step 1: Write `tests/jevtest.py`:**

```python
"""Shared fixtures for the Jev skill tests: a git repo, a fake HOME, a loopback stub.

Never the real API: every environment built here sets JEV_TEST_MODE=1 (the
registry is never read, and only http://127.0.0.1 may be reached) and drops
the caller's TYPESAFE_API_KEY. Paths are forward-slashed for Git Bash.
"""
import http.server
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time

sys.dont_write_bytecode = True

SKILL = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO_ROOT = os.environ.get("JEV_REPO_ROOT") or os.path.abspath(os.path.join(SKILL, "..", "..", ".."))
LIB = os.path.join(REPO_ROOT, "hooks", "lib", "agent-model.sh")
ROUTE = os.path.join(SKILL, "jev_route.py")
KEY = "fake-key-0123456789"
MARK = "PROMPT-MARKER-7391"
REGISTRATION = {"hooks": {"PreToolUse": [{"matcher": "Agent", "hooks": [{
    "type": "command", "command": 'f="$HOME/.claude/skills/jev/jev_route.py"; [ -f "$f" ] && python3 "$f"; exit 0',
    "timeout": 5}]}]}}


def fwd(path):
    return path.replace("\\", "/")


def git(*args):
    return subprocess.run(["git"] + list(args), capture_output=True, check=True).stdout.decode("utf-8").strip()


class Sandbox:
    """A repo with one commit and a HOME holding the resolver lib; flags switch the Jev pieces."""

    def __init__(self, case, register=True, route=True, skill=True, lib_in_home=True):
        if not os.path.isfile(LIB):
            case.skipTest("hooks/lib/agent-model.sh not found (set JEV_REPO_ROOT)")
        tmp = fwd(tempfile.mkdtemp(prefix="jev-"))
        case.addCleanup(shutil.rmtree, tmp, True)
        self.repo, self.home = tmp + "/repo", tmp + "/home"
        os.makedirs(self.repo + "/.claude")
        os.makedirs(self.home + "/.claude/hooks/lib")
        git("init", "-q", "-b", "main", self.repo)
        git("-C", self.repo, "-c", "user.name=t", "-c", "user.email=t@example.invalid",
            "-c", "commit.gpgsign=false", "commit", "-q", "--allow-empty", "-m", "init")
        self.gd = fwd(git("-C", self.repo, "rev-parse", "--path-format=absolute", "--git-common-dir"))
        self.home_lib = self.home + "/.claude/hooks/lib/agent-model.sh"
        if lib_in_home:
            shutil.copyfile(LIB, self.home_lib)
        self.skill_file = self.home + "/.claude/skills/jev/jev_route.py"
        if skill:
            os.makedirs(os.path.dirname(self.skill_file))
            open(self.skill_file, "w").close()
        self.settings = self.repo + "/.claude/settings.local.json"
        if register:
            with open(self.settings, "w", encoding="utf-8", newline="\n") as fh:
                json.dump(REGISTRATION, fh)
        self.config = self.gd + "/jev/config.json"
        if route is not None:
            os.makedirs(self.gd + "/jev", exist_ok=True)
            with open(self.config, "w", encoding="utf-8", newline="\n") as fh:
                json.dump({"model": "jev-1.13.0", "threshold": 0.8, "route": route, "legs": False}, fh)

    def env(self, endpoint="http://127.0.0.1:9/v1/systemone", key=KEY):
        drop = {"TYPESAFE_API_KEY", "CLAUDE_PROJECT_DIR", "CLAUDE_CODE_SUBAGENT_MODEL",
                "CLAUDE_CODE_SUBAGENT_MODEL_FORCE", "JEV_ENDPOINT"}
        env = {k: v for k, v in os.environ.items() if k not in drop}
        env.update({"HOME": self.home, "JEV_TEST_MODE": "1", "JEV_ENDPOINT": endpoint,
                    "PYTHONDONTWRITEBYTECODE": "1"})
        if key:
            env["TYPESAFE_API_KEY"] = key
        return env

    def events(self):
        d = self.gd + "/jev/events"
        return sorted(os.listdir(d)) if os.path.isdir(d) else []

    def lib_cli(self, stype):
        cp = subprocess.run(["bash", LIB, stype, self.repo], capture_output=True, env=self.env(), timeout=20)
        return cp.stdout.decode("utf-8", "replace").strip()


class Stub:
    """A loopback /v1/systemone: mode ok | hang | drip | 500 | garbage. Records requests."""

    def __init__(self, case, mode, body=None):
        self.mode, self.body, self.requests = mode, body, []
        stub = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_POST(self):
                n = int(self.headers.get("Content-Length") or 0)
                stub.requests.append({"auth": self.headers.get("Authorization"), "body": self.rfile.read(n)})
                if stub.mode == "hang":
                    time.sleep(10)
                    return
                if stub.mode == "drip":  # headers at once, then one byte every 0.5 s
                    self.send_response(200)
                    self.send_header("Content-Length", "1000")
                    self.end_headers()
                    for _ in range(20):
                        self.wfile.write(b" ")
                        self.wfile.flush()
                        time.sleep(0.5)
                    return
                if stub.mode == "500":
                    self.send_response(500)
                    self.send_header("Content-Length", "0")
                    self.end_headers()
                    return
                data = b"not json" if stub.mode == "garbage" else json.dumps(stub.body).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.server.daemon_threads = True
        self.server.block_on_close = False
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.url = "http://127.0.0.1:%d/v1/systemone" % self.server.server_address[1]
        case.addCleanup(self.close)

    def close(self):
        self.server.shutdown()
        self.server.server_close()


def ok_answer(choice="opus", conf=0.95):
    return {"model": "jev-1.13.0", "answers": {
        "model": {"type": "choice", "choice": choice, "confidence": conf, "probabilities": {choice: conf}},
        "effort": {"type": "choice", "choice": "medium", "confidence": 0.7, "probabilities": {}}},
        "usage": {"input_tokens": 1, "output_tokens": 1}}


def agent_payload(sandbox, stype="general-purpose", model=None, prompt="Summarise the README. " + MARK):
    ti = {"subagent_type": stype, "prompt": prompt, "description": "d", "zz": 1}
    if model:
        ti["model"] = model
    return {"session_id": "t", "hook_event_name": "PreToolUse", "tool_name": "Agent",
            "tool_input": ti, "cwd": sandbox.repo}


def run_hook(sandbox, payload, endpoint, key=KEY, raw=None):
    """Run jev_route.py as the registration would. -> (CompletedProcess, seconds)."""
    t0 = time.monotonic()
    data = raw if raw is not None else json.dumps(payload).encode("utf-8")
    cp = subprocess.run([sys.executable, ROUTE], input=data, capture_output=True,
                        env=sandbox.env(endpoint, key), timeout=20)
    return cp, time.monotonic() - t0
```

- [ ] **Step 2: Write the failing tests** (`tests/test_e2e.py`):

```python
"""jev_route end to end: the real resolver lib, a loopback stub, the real process (v4.4.0 Task 7)."""
import json
import os
import sys
import time
import unittest

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
sys.path.insert(0, HERE)

import jev_route as jr  # noqa: E402
import jevtest as jt  # noqa: E402


def model_of(cp):
    return json.loads(cp.stdout.decode("utf-8"))["hookSpecificOutput"]["updatedInput"]["model"] if cp.stdout else None


def last_event(sb):
    names = sb.events()
    with open(sb.gd + "/jev/events/" + names[-1], encoding="utf-8") as fh:
        return fh.read()


class ResolverAndTransportTests(unittest.TestCase):
    def test_resolver_answers_like_model_floor(self):
        sb = jt.Sandbox(self)
        res = jr.run_resolver("general-purpose", sb.repo, sb.env())
        self.assertEqual((res.kind, res.model, res.jev, res.effort), ("floor", "sonnet", True, ""))
        self.assertEqual(jt.fwd(res.gd), sb.gd)

    def test_resolver_without_lib_is_none(self):
        sb = jt.Sandbox(self, lib_in_home=False)
        self.assertIsNone(jr.run_resolver("general-purpose", sb.repo, sb.env()))

    def test_post_sends_bearer_and_returns_body(self):
        stub = jt.Stub(self, "ok", jt.ok_answer("opus", 0.9))
        raw = jr.post_with_deadline(stub.url, b'{"x": 1}', jt.KEY, 2.0, {"JEV_TEST_MODE": "1"})
        self.assertEqual(json.loads(raw.decode("utf-8"))["answers"]["model"]["choice"], "opus")
        self.assertEqual(stub.requests[0]["auth"], "Bearer " + jt.KEY)

    def test_post_with_deadline_bounds_a_hang(self):
        stub = jt.Stub(self, "hang")
        t0 = time.monotonic()
        with self.assertRaises(jr.JevTimeout):
            jr.post_with_deadline(stub.url, b"{}", jt.KEY, 0.5, {"JEV_TEST_MODE": "1"})
        self.assertLess(time.monotonic() - t0, 1.5)


class HookTests(unittest.TestCase):
    def test_hook_routes_a_spawn_end_to_end(self):
        sb = jt.Sandbox(self)
        stub = jt.Stub(self, "ok", jt.ok_answer("opus", 0.95))
        cp, _ = jt.run_hook(sb, jt.agent_payload(sb, prompt="x " * 4000 + jt.MARK), stub.url)
        self.assertEqual((cp.returncode, model_of(cp)), (0, "opus"))
        req = stub.requests[0]
        body = json.loads(req["body"].decode("utf-8"))
        self.assertEqual((req["auth"], body["model"]), ("Bearer " + jt.KEY, "jev-1.13.0"))
        self.assertLessEqual(len(body["state"]), 4000)
        ev = last_event(sb)
        self.assertNotIn(jt.MARK, ev)
        self.assertNotIn(jt.KEY, ev)
        self.assertEqual(json.loads(ev)["reason"], "applied")

    def test_hook_hang_falls_back_to_floor_in_time(self):
        sb = jt.Sandbox(self)
        stub = jt.Stub(self, "hang")
        cp, secs = jt.run_hook(sb, jt.agent_payload(sb), stub.url)
        self.assertEqual(model_of(cp), "sonnet")
        self.assertLess(secs, 5.0)  # the registration's hook timeout
        self.assertEqual(json.loads(last_event(sb))["reason"], "timeout")

    def test_hook_slow_drip_falls_back_to_floor_in_time(self):
        sb = jt.Sandbox(self)
        stub = jt.Stub(self, "drip")
        cp, secs = jt.run_hook(sb, jt.agent_payload(sb), stub.url)
        self.assertEqual(model_of(cp), "sonnet")
        self.assertLess(secs, 5.0)
        self.assertEqual(json.loads(last_event(sb))["reason"], "timeout")

    def test_hook_http_500_falls_back(self):
        sb = jt.Sandbox(self)
        stub = jt.Stub(self, "500")
        cp, _ = jt.run_hook(sb, jt.agent_payload(sb), stub.url)
        self.assertEqual(model_of(cp), "sonnet")
        self.assertEqual(json.loads(last_event(sb))["reason"], "http-error")

    def test_hook_garbage_falls_back(self):
        sb = jt.Sandbox(self)
        stub = jt.Stub(self, "garbage")
        cp, _ = jt.run_hook(sb, jt.agent_payload(sb), stub.url)
        self.assertEqual(model_of(cp), "sonnet")
        self.assertEqual(json.loads(last_event(sb))["reason"], "bad-response")

    def test_hook_off_sends_nothing_writes_nothing(self):
        sb = jt.Sandbox(self, route=False)
        stub = jt.Stub(self, "ok", jt.ok_answer())
        cp, _ = jt.run_hook(sb, jt.agent_payload(sb), stub.url)
        self.assertEqual((cp.returncode, cp.stdout, stub.requests, sb.events()), (0, b"", [], []))

    def test_hook_unregistered_checkout_is_off(self):
        sb = jt.Sandbox(self, register=False)
        stub = jt.Stub(self, "ok", jt.ok_answer())
        cp, _ = jt.run_hook(sb, jt.agent_payload(sb), stub.url)
        self.assertEqual((cp.stdout, stub.requests, sb.events()), (b"", [], []))

    def test_hook_explicit_model_sends_nothing(self):
        sb = jt.Sandbox(self)
        stub = jt.Stub(self, "ok", jt.ok_answer("haiku", 0.99))
        cp, _ = jt.run_hook(sb, jt.agent_payload(sb, model="opus"), stub.url)
        self.assertEqual((cp.stdout, stub.requests), (b"", []))
        self.assertEqual(json.loads(last_event(sb))["reason"], "explicit")

    def test_hook_garbage_stdin_exits_zero_silently(self):
        sb = jt.Sandbox(self)
        cp, _ = jt.run_hook(sb, None, "http://127.0.0.1:9/v1/systemone", raw=b"\xff\xfe not json")
        self.assertEqual((cp.returncode, cp.stdout), (0, b""))


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 3: Run and watch it fail.** Expected: `AttributeError: module 'jev_route' has no attribute 'run_resolver'`, and the hook tests fail with empty stdout, because there is no `main`.

- [ ] **Step 4: Append to `jev_route.py`:**

```python
RESOLUTION_RE = re.compile(r"^(own|floor|env|none) (\S+) ([01]) (\S+) (.+)$")


def post_with_deadline(url, body, key, timeout, env):
    """POST in a worker thread joined with `timeout`. urllib's own timeout is per
    socket operation (a slow drip never trips it) and name resolution has none,
    so only the join bounds the wall clock. Raises JevTimeout or HttpError."""
    box = {}
    handlers = [urllib.request.ProxyHandler({})] if env.get("JEV_TEST_MODE") == "1" else []
    opener = urllib.request.build_opener(*handlers)

    def work():
        req = urllib.request.Request(url, data=body, method="POST", headers={
            "Authorization": "Bearer " + key, "Content-Type": "application/json"})
        try:
            with opener.open(req, timeout=timeout) as resp:
                box["status"], box["raw"] = resp.status, resp.read(MAX_RESPONSE)
        except urllib.error.HTTPError as exc:
            box["status"] = exc.code
        except Exception as exc:  # noqa: BLE001 -- any failure is "no answer"
            box["exc"] = exc

    worker = threading.Thread(target=work, daemon=True)
    worker.start()
    worker.join(timeout)
    if worker.is_alive():
        raise JevTimeout()
    exc = box.get("exc")
    if exc is not None:
        if isinstance(exc, (TimeoutError, socket.timeout)) or isinstance(getattr(exc, "reason", None), (TimeoutError, socket.timeout)):
            raise JevTimeout()
        raise HttpError(type(exc).__name__)
    if box.get("status") != 200:
        raise HttpError(str(box.get("status")))
    return box["raw"]


def run_resolver(subagent_type, cwd, env):
    """Run model-floor's own resolution (hooks/lib/agent-model.sh) -- the project's
    copy when CLAUDE_PROJECT_DIR has one (the S-24 precedence), else the user-level
    one. Arguments go in argv, never into program text. None when unavailable."""
    cands = []
    if env.get("CLAUDE_PROJECT_DIR"):
        cands.append(os.path.join(env["CLAUDE_PROJECT_DIR"], "hooks", "lib", "agent-model.sh"))
    home = env.get("HOME") or os.path.expanduser("~")
    cands.append(os.path.join(home, ".claude", "hooks", "lib", "agent-model.sh"))
    lib = next((c for c in cands if os.path.isfile(c)), None)
    bash = shutil.which("bash", path=env.get("PATH"))
    if not lib or not bash:
        return None
    try:
        cp = subprocess.run([bash, lib, subagent_type, cwd], capture_output=True,
                            timeout=RESOLVER_TIMEOUT, env=dict(env))
    except (OSError, subprocess.SubprocessError):
        return None
    m = RESOLUTION_RE.match(cp.stdout.decode("utf-8", "replace").strip())
    if not m:
        return None
    kind, model, jev, effort, gd = m.groups()
    return Resolution(kind, "" if model == "-" else model, jev == "1",
                      "" if effort == "-" else effort, "" if gd == "-" else gd)


def main():
    try:
        out, ev, gd = run(sys.stdin.buffer.read(), dict(os.environ))
    except Exception:  # noqa: BLE001 -- never fail a spawn
        return 0
    if out:
        sys.stdout.buffer.write(out)
        sys.stdout.buffer.flush()
    if ev is not None and gd:
        try:
            write_event(gd, ev)
        except OSError:
            pass
    if out and ev is not None:
        sys.stderr.write("jev: {} {} -> {} ({})\n".format(
            ev["subagent_type"], ev["default"] or "-", ev["emitted"], ev["reason"]))
    return 0


if __name__ == "__main__":
    _rc = main()
    sys.stdout.flush()
    sys.stderr.flush()
    os._exit(_rc)  # never wait for a request thread still blocked in the network
```

- [ ] **Step 5: Run.** Expected: `Ran 76 tests … OK`. If the E2E rows fail on HOME or path spelling under Git Bash, print `cp.stderr` from `run_hook` and fix it in `jevtest.py`, not in the router. The router must accept the env the registration really passes, which Task 11's live smoke checks.

- [ ] **Step 6: Guard against the real API in tests.** Run Grep for `api.typesafe.ai` in `user-level-reference/skills/jev/tests/`. Expected: hits only in `test_route.py` (asserted to be refused, or compared to `jr.ENDPOINT`). Run Grep for `JEV_TEST_MODE` in `jevtest.py`. Expected: set in `Sandbox.env`.

- [ ] **Step 7: Bump J-PY** `JPY_WANT=76`. `run-block.sh … v4.4.0 J-PY`: 4 passed, and no `__pycache__`.

- [ ] **Step 8: Commit** (`feat(jev): router transport with a joined deadline, model-floor's resolver reused via its CLI, E2E against a loopback stub (v4.4.0)`). Paths: `user-level-reference/skills/jev/jev_route.py user-level-reference/skills/jev/tests/jevtest.py user-level-reference/skills/jev/tests/test_e2e.py scripts/test-hooks.sh`.

---

### Task 8: `jev_ctl.py` (on / off / status / report) and the `/jev` SKILL.md

**Files:**
- Create: `user-level-reference/skills/jev/jev_ctl.py`
- Create: `user-level-reference/skills/jev/SKILL.md`
- Create: `user-level-reference/skills/jev/tests/test_ctl.py`
- Modify: `scripts/test-hooks.sh`, J-PY `JPY_WANT=76` → `89`

**Interfaces:**
- Consumes: `jev_route.load_key`, `jev_route._winreg_key`, `jev_route.family`, `jev_route.ORDER`; `jevtest.Sandbox`.
- Produces:
  - `REG_COMMAND` (a line of its own, `REG_COMMAND = '…'`, which check 64 extracts), `MARKER`, `CONFIG_ON`, `CtlError`;
  - `main(argv=None, cwd=None, env=None, out=None, registry=None) -> int` (0 ok, 1 refused or error, 2 usage);
  - `ledger_slug(top) -> str`, `_local(ts) -> naive local datetime`.

- [ ] **Step 1: Write the failing tests** (`tests/test_ctl.py`):

```python
"""/jev on | off | status | report (v4.4.0 Task 8)."""
import datetime
import io
import json
import os
import sys
import unittest

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
sys.path.insert(0, HERE)

import jev_ctl as jc  # noqa: E402
import jevtest as jt  # noqa: E402

EV = {"ts": "2026-10-02T10:00:30.000Z", "subagent_type": "general-purpose", "kind": "floor", "default": "sonnet",
      "agent_effort": "", "choice": None, "confidence": None, "probabilities": {}, "effort_choice": None,
      "effort_confidence": None, "applied": False, "reason": "kept", "emitted": None, "latency_s": 0.3}


class CtlTests(unittest.TestCase):
    def setUp(self):
        self.t = jt.Sandbox(self, register=False, route=None)

    def ctl(self, *argv, env=None, registry=lambda: ""):
        out = io.StringIO()
        rc = jc.main(list(argv), cwd=self.t.repo, env=env or self.t.env(), out=out, registry=registry)
        return rc, out.getvalue()

    def read(self, path):
        with open(path, "rb") as fh:
            return fh.read()

    def write(self, path, data):
        with open(path, "wb") as fh:
            fh.write(data)

    def exclude_lines(self):
        return self.read(self.t.gd + "/info/exclude").decode("utf-8").splitlines()

    def test_on_writes_config_registration_and_exclude(self):
        rc, text = self.ctl("on")
        self.assertEqual(rc, 0, text)
        self.assertEqual(json.loads(self.read(self.t.config)), jc.CONFIG_ON)
        obj = json.loads(self.read(self.t.settings))
        self.assertEqual(obj["hooks"]["PreToolUse"], [{"matcher": "Agent", "hooks": [
            {"type": "command", "command": jc.REG_COMMAND, "timeout": 5}]}])
        self.assertIn(".claude/settings.local.json", self.exclude_lines())

    def test_on_twice_is_idempotent(self):
        self.ctl("on")
        first = self.read(self.t.settings)
        rc, text = self.ctl("on")
        self.assertEqual((rc, self.read(self.t.settings)), (0, first))
        self.assertEqual(self.exclude_lines().count(".claude/settings.local.json"), 1)
        self.assertIn("already registered", text)

    def test_round_trip_restores_existing_bytes(self):
        original = ('\ufeff{\r\n  "permissions": {"allow": ["Bash(ls)"]},\r\n  "hooks": {"PreToolUse": '
                    '[{"matcher": "Agent", "hooks": [{"type": "command", "command": "echo mine"}]}]}\r\n}\r\n').encode("utf-8")
        self.write(self.t.settings, original)
        self.ctl("on")
        self.assertNotEqual(self.read(self.t.settings), original)
        rc, text = self.ctl("off")
        self.assertEqual((rc, self.read(self.t.settings)), (0, original), text)

    def test_round_trip_deletes_a_file_on_created(self):
        self.assertFalse(os.path.exists(self.t.settings))
        self.ctl("on")
        self.assertTrue(os.path.exists(self.t.settings))
        self.ctl("off")
        self.assertFalse(os.path.exists(self.t.settings))

    def test_off_after_user_edit_removes_only_the_jev_entry(self):
        self.ctl("on")
        obj = json.loads(self.read(self.t.settings))
        obj["permissions"] = {"allow": ["Bash(git status)"]}
        self.write(self.t.settings, json.dumps(obj).encode("utf-8"))
        rc, text = self.ctl("off")
        self.assertEqual(rc, 0, text)
        self.assertEqual(json.loads(self.read(self.t.settings)), {"permissions": {"allow": ["Bash(git status)"]}})
        self.assertIn("removed only the Jev entry", text)

    def test_off_sets_route_false_and_the_floor_returns(self):
        self.ctl("on")
        self.assertEqual(self.t.lib_cli("general-purpose").split()[2], "1")
        self.ctl("off")
        self.assertIs(json.loads(self.read(self.t.config))["route"], False)
        self.assertEqual(self.t.lib_cli("general-purpose").split()[2], "0")

    def test_on_refuses_without_resolver(self):
        os.remove(self.t.home_lib)
        rc, text = self.ctl("on")
        self.assertEqual(rc, 1)
        self.assertIn("agent-model.sh", text)
        self.assertFalse(os.path.exists(self.t.settings) or os.path.exists(self.t.config))

    def test_on_refuses_without_installed_router(self):
        os.remove(self.t.skill_file)
        rc, text = self.ctl("on")
        self.assertEqual(rc, 1)
        self.assertIn("not installed", text)
        self.assertFalse(os.path.exists(self.t.settings) or os.path.exists(self.t.config))

    def test_on_refuses_a_pre_v4_4_model_floor(self):
        os.makedirs(self.t.repo + "/hooks")
        self.write(self.t.repo + "/hooks/model-floor.sh", b"#!/usr/bin/env bash\n# v4.3.0 copy, no shared lib\n")
        rc, text = self.ctl("on")
        self.assertEqual(rc, 1)
        self.assertIn("predates v4.4.0", text)
        self.assertFalse(os.path.exists(self.t.settings) or os.path.exists(self.t.config))

    def test_on_refuses_a_non_object_settings_file(self):
        self.write(self.t.settings, b"[1, 2]")
        rc, _ = self.ctl("on")
        self.assertEqual((rc, self.read(self.t.settings)), (1, b"[1, 2]"))
        self.assertFalse(os.path.exists(self.t.config))

    def test_status_never_prints_the_key(self):
        env = self.t.env()
        env["TYPESAFE_API_KEY"] = "env-secret-4567"
        self.ctl("on", env=env)
        _, text = self.ctl("status", env=env, registry=lambda: "hkcu-secret-8910")
        self.assertNotIn("env-secret-4567", text)
        self.assertNotIn("hkcu-secret-8910", text)
        self.assertIn("TYPESAFE_API_KEY: set (environment)", text)
        self.assertIn("routing spawns in this checkout: yes", text)
        del env["TYPESAFE_API_KEY"]
        _, text = self.ctl("status", env=env, registry=lambda: "hkcu-secret-8910")
        self.assertNotIn("hkcu-secret-8910", text)
        self.assertIn("TYPESAFE_API_KEY: set (HKCU\\Environment)", text)

    def _events(self, evs):
        d = self.t.gd + "/jev/events"
        os.makedirs(d, exist_ok=True)
        for i, ev in enumerate(evs):
            self.write("{}/20261002T10000{}000000Z-{}.json".format(d, i, i), json.dumps(ev).encode("utf-8"))

    def test_report_summarises_events(self):
        self._events([
            dict(EV, choice="opus", confidence=0.95, applied=True, reason="applied", emitted="opus"),
            dict(EV, subagent_type="coder", kind="own", default="opus", choice="sonnet", confidence=0.9,
                 applied=True, reason="applied", emitted="sonnet"),
            dict(EV, reason="explicit"),
            dict(EV, choice="haiku", confidence=0.6, reason="low-confidence", emitted="sonnet",
                 agent_effort="high", effort_choice="medium"),
        ])
        rc, text = self.ctl("report")
        self.assertEqual(rc, 0, text)
        for line in ("jev report: 4 spawns seen", "applied: 2 (up 1, down 1)",
                     "not applied: explicit 1, low-confidence 1",
                     "model confidence: <0.5: 0, 0.5-0.8: 1, >=0.8: 2",
                     "differs from the agent file's effort: 1 of 1"):
            self.assertIn(line, text)

    def test_report_joins_retro_ledger_rows(self):
        self._events([dict(EV, subagent_type="coder", kind="own", default="opus", choice="sonnet",
                           confidence=0.9, applied=True, reason="applied", emitted="sonnet")])
        top = jc.locate(self.t.repo)[0]
        base = jc._local(EV["ts"]).replace(second=0, microsecond=0)
        row = (base + datetime.timedelta(minutes=5)).strftime("%Y-%m-%d %H:%M") + \
            " | coder | agent-x | dead=[] | blocks=[x.sh] | budget=0 | errors=1"
        far = (base + datetime.timedelta(hours=3)).strftime("%Y-%m-%d %H:%M") + " | coder | agent-y | dead=[] | blocks=[] | budget=0 | errors=1"
        other = (base + datetime.timedelta(minutes=5)).strftime("%Y-%m-%d %H:%M") + " | tester | agent-z | dead=[] | blocks=[] | budget=0 | errors=1"
        ledger = "{}/.claude/projects/{}/memory".format(self.t.home, jc.ledger_slug(top))
        os.makedirs(ledger)
        self.write(ledger + "/retro.md", "\n".join([row, far, other, ""]).encode("utf-8"))
        _, text = self.ctl("report")
        self.assertIn("after a routed spawn of the same type: 1 (", text)
        self.assertIn(row, text)
        self.assertNotIn("agent-y", text)
        self.assertNotIn("agent-z", text)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run and watch it fail.** Expected: `ModuleNotFoundError: No module named 'jev_ctl'`.

- [ ] **Step 3: Create `jev_ctl.py`:**

```python
#!/usr/bin/env python3
"""jev_ctl.py -- `/jev on | off | status | report` (toolkit v4.4.0, Jev Phase 1a).

The switch is per CLONE: <git common dir>/jev/config.json. The router is
registered per CHECKOUT: ONE PreToolUse(Agent) entry in this checkout's
.claude/settings.local.json. model-floor.sh steps aside only when both are in
place and the router is installed (hooks/lib/agent-model.sh am_jev_routing,
ruling R-2), so a half-on state floors instead of inheriting the orchestrator's
model. `off` writes "route": false FIRST, then restores settings.local.json
byte for byte when nobody edited it since `on`, else removes only the Jev
entry. Never prints the API key.
"""
import sys

sys.dont_write_bytecode = True

import base64  # noqa: E402
import datetime  # noqa: E402
import hashlib  # noqa: E402
import json  # noqa: E402
import os  # noqa: E402
import re  # noqa: E402
import shutil  # noqa: E402
import subprocess  # noqa: E402
from collections import Counter  # noqa: E402

import jev_route  # noqa: E402

REG_COMMAND = 'f="$HOME/.claude/skills/jev/jev_route.py"; [ -f "$f" ] && python3 "$f"; exit 0'
MARKER = "skills/jev/jev_route.py"
CONFIG_ON = {"model": "jev-1.13.0", "threshold": 0.8, "route": True, "legs": False}
EXCLUDE_LINE = ".claude/settings.local.json"
LEDGER_RE = re.compile(r"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}) \| ([^|]+?) \| ")
USAGE = "usage: /jev on | off | status | report   (Phase 1b `on legs` is not in this release)\n"


class CtlError(Exception):
    pass


def _git(cwd, *args):
    try:
        cp = subprocess.run(["git", "-C", cwd] + list(args), capture_output=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return None
    return cp.stdout.decode("utf-8", "replace").strip() if cp.returncode == 0 else None


def locate(cwd):
    """-> (checkout top level, absolute git common dir)."""
    top = _git(cwd, "rev-parse", "--show-toplevel")
    gd = _git(cwd, "rev-parse", "--path-format=absolute", "--git-common-dir")
    if not top or not gd:
        raise CtlError("not inside a git checkout -- /jev is switched per clone")
    return top, gd


def _home(env):
    return env.get("HOME") or os.path.expanduser("~")


def _read(path):
    try:
        with open(path, "rb") as fh:
            return fh.read()
    except FileNotFoundError:
        return None


def _write(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as fh:
        fh.write(data)


def _dumps(obj):
    return (json.dumps(obj, indent=2, ensure_ascii=False) + "\n").encode("utf-8")


def resolver_lib(env, top):
    for cand in (os.path.join(top, "hooks", "lib", "agent-model.sh"),
                 os.path.join(_home(env), ".claude", "hooks", "lib", "agent-model.sh")):
        if os.path.isfile(cand):
            return cand
    return None


def _active_model_floor(env, top):
    """The model-floor.sh a spawn here runs: the project's copy wins (S-24)."""
    for cand in (os.path.join(top, "hooks", "model-floor.sh"),
                 os.path.join(_home(env), ".claude", "hooks", "model-floor.sh")):
        if os.path.isfile(cand):
            return cand
    return None


def parse_settings(data):
    if data is None or not data.strip():
        return {}
    try:
        obj = json.loads(data.decode("utf-8-sig"))
    except (UnicodeDecodeError, ValueError):
        raise CtlError(".claude/settings.local.json is not valid JSON -- fix it by hand first")
    if not isinstance(obj, dict):
        raise CtlError(".claude/settings.local.json is not a JSON object -- fix it by hand first")
    return obj


def _is_jev(hook):
    return isinstance(hook, dict) and MARKER in str(hook.get("command", ""))


def _pre(obj):
    hooks = obj.get("hooks")
    pre = hooks.get("PreToolUse") if isinstance(hooks, dict) else None
    return pre if isinstance(pre, list) else []


def has_entry(obj):
    return any(isinstance(g, dict) and isinstance(g.get("hooks"), list) and any(_is_jev(h) for h in g["hooks"])
               for g in _pre(obj))


def add_entry(obj):
    new = json.loads(json.dumps(obj))
    hooks = new.setdefault("hooks", {})
    if not isinstance(hooks, dict):
        raise CtlError('.claude/settings.local.json: "hooks" is not an object -- nothing was changed')
    pre = hooks.setdefault("PreToolUse", [])
    if not isinstance(pre, list):
        raise CtlError('.claude/settings.local.json: "hooks.PreToolUse" is not a list -- nothing was changed')
    pre.append({"matcher": "Agent", "hooks": [{"type": "command", "command": REG_COMMAND, "timeout": 5}]})
    return new


def remove_entry(obj):
    new = json.loads(json.dumps(obj))
    hooks = new.get("hooks")
    if not isinstance(hooks, dict) or not isinstance(hooks.get("PreToolUse"), list):
        return new
    kept = []
    for g in hooks["PreToolUse"]:
        if isinstance(g, dict) and isinstance(g.get("hooks"), list) and any(_is_jev(h) for h in g["hooks"]):
            rest = [h for h in g["hooks"] if not _is_jev(h)]
            if not rest:
                continue
            g = dict(g, hooks=rest)
        kept.append(g)
    if kept:
        hooks["PreToolUse"] = kept
    else:
        del hooks["PreToolUse"]
    if not hooks:
        del new["hooks"]
    return new


def _snapshot_path(gd, top):
    return os.path.join(gd, "jev", "snapshots", hashlib.sha256(top.encode("utf-8")).hexdigest()[:16] + ".json")


def _config_path(gd):
    return os.path.join(gd, "jev", "config.json")


def _read_config(gd):
    try:
        cfg = json.loads((_read(_config_path(gd)) or b"").decode("utf-8-sig"))
    except (UnicodeDecodeError, ValueError):
        return None
    return cfg if isinstance(cfg, dict) else None


def _ensure_excluded(top, gd):
    """Spec step 3: exclude settings.local.json unless git already ignores it."""
    try:
        if subprocess.run(["git", "-C", top, "check-ignore", "-q", EXCLUDE_LINE],
                          capture_output=True, timeout=10).returncode == 0:
            return False
    except (OSError, subprocess.SubprocessError):
        pass
    path = os.path.join(gd, "info", "exclude")
    data = _read(path) or b""
    if EXCLUDE_LINE in data.decode("utf-8", "replace").splitlines():
        return False
    sep = b"" if not data or data.endswith(b"\n") else b"\n"
    _write(path, data + sep + EXCLUDE_LINE.encode("utf-8") + b"\n")
    return True


def _key_source(env, registry):
    if (env.get("TYPESAFE_API_KEY") or "").strip():
        return "environment"
    if ((registry or jev_route._winreg_key)() or "").strip():
        return "HKCU\\Environment"
    return None


def cmd_on(top, gd, env, out, registry):
    if not os.path.isfile(os.path.join(_home(env), ".claude", "skills", "jev", "jev_route.py")):
        raise CtlError("~/.claude/skills/jev/jev_route.py is not installed -- copy user-level-reference/skills/jev/ "
                       "to ~/.claude/skills/jev/ first; nothing was changed")
    if not resolver_lib(env, top):
        raise CtlError("no hooks/lib/agent-model.sh in this project or in ~/.claude/hooks/lib/ -- the router reuses "
                       "model-floor's resolution and cannot run without it; nothing was changed")
    mf = _active_model_floor(env, top)
    if mf and b"agent-model.sh" not in (_read(mf) or b""):
        raise CtlError("{} predates v4.4.0 (it steps aside on the switch alone, so a sibling worktree would lose "
                       "the floor) -- update it first (/sync-template, or the v4.4.0 hooks in ~/.claude/hooks/); "
                       "nothing was changed".format(mf))
    path = os.path.join(top, ".claude", "settings.local.json")
    before = _read(path)
    obj = parse_settings(before)
    if has_entry(obj):
        out.write("jev: the router is already registered in .claude/settings.local.json\n")
    else:
        new = add_entry(obj)
        snap = {"existed": before is not None,
                "before_b64": base64.b64encode(before or b"").decode("ascii"), "after": new}
        _write(_snapshot_path(gd, top), _dumps(snap))
        _write(path, _dumps(new))
        out.write("jev: registered the router in .claude/settings.local.json (PreToolUse, matcher Agent)\n")
    _write(_config_path(gd), _dumps(CONFIG_ON))
    if _ensure_excluded(top, gd):
        out.write("jev: added .claude/settings.local.json to .git/info/exclude\n")
    out.write("jev: ON for this clone -- spawns that pass no `model` are routed (one step at most from the "
              "agent's default; review/architect types never below sonnet); other checkouts of this clone "
              "need their own /jev on\n")
    real = env.get("CLAUDE_CODE_SUBAGENT_MODEL", "")
    if re.fullmatch(r"haiku|sonnet|opus|fable|claude-\S+", real):
        out.write("jev: note -- CLAUDE_CODE_SUBAGENT_MODEL={} covers general-purpose spawns; Jev leaves "
                  "those alone\n".format(real))
    if not _key_source(env, registry):
        out.write("jev: note -- no TYPESAFE_API_KEY: spawns get the project floor until one is set\n")
    return 0


def cmd_off(top, gd, env, out, registry):
    cfg = _read_config(gd) or dict(CONFIG_ON)
    cfg["route"] = False
    _write(_config_path(gd), _dumps(cfg))  # FIRST: model-floor floors again whatever happens below
    path = os.path.join(top, ".claude", "settings.local.json")
    snap_path = _snapshot_path(gd, top)
    snap = None
    raw = _read(snap_path)
    if raw:
        try:
            snap = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, ValueError):
            snap = None
    cur = _read(path)
    if cur is not None:
        obj = parse_settings(cur)
        if isinstance(snap, dict) and obj == snap.get("after"):
            if snap.get("existed"):
                _write(path, base64.b64decode(snap.get("before_b64", "")))
            else:
                os.remove(path)
            out.write("jev: .claude/settings.local.json restored to its state before /jev on\n")
        elif has_entry(obj):
            _write(path, _dumps(remove_entry(obj)))
            out.write("jev: .claude/settings.local.json changed since /jev on -- removed only the Jev entry "
                      "(the file was re-serialised)\n")
    if os.path.exists(snap_path):
        os.remove(snap_path)
    out.write("jev: OFF for this clone -- model-floor applies the project default again; events stay in "
              "<git common dir>/jev/events/\n")
    return 0


def _events(gd):
    d = os.path.join(gd, "jev", "events")
    evs = []
    for name in sorted(os.listdir(d)) if os.path.isdir(d) else []:
        try:
            ev = json.loads(_read(os.path.join(d, name)).decode("utf-8"))
        except (AttributeError, OSError, UnicodeDecodeError, ValueError):
            continue
        if isinstance(ev, dict):
            evs.append(ev)
    return evs


def cmd_status(top, gd, env, out, registry):
    cfg = _read_config(gd)
    route = bool(cfg and cfg.get("route") is True)
    out.write("jev: switch (this clone): {}\n".format("on" if route else "off"))
    if cfg:
        out.write("jev: config: model {} threshold {} legs {}\n".format(cfg.get("model"), cfg.get("threshold"), cfg.get("legs")))
    try:
        registered = has_entry(parse_settings(_read(os.path.join(top, ".claude", "settings.local.json"))))
    except CtlError:
        registered = False
    installed = os.path.isfile(os.path.join(_home(env), ".claude", "skills", "jev", "jev_route.py"))
    lib = resolver_lib(env, top)
    py = shutil.which("python3", path=env.get("PATH"))
    src = _key_source(env, registry)
    out.write("jev: router registered in this checkout: {}\n".format("yes" if registered else "no"))
    out.write("jev: router installed (~/.claude/skills/jev/jev_route.py): {}\n".format("yes" if installed else "no"))
    out.write("jev: resolver: {}\n".format(lib or "MISSING"))
    out.write("jev: TYPESAFE_API_KEY: {}\n".format("set ({})".format(src) if src else "not set"))
    evs = _events(gd)
    if evs:
        e = evs[-1]
        out.write("jev: last event: {} {} {} applied={}\n".format(e.get("ts"), e.get("subagent_type"), e.get("reason"), e.get("applied")))
    else:
        out.write("jev: last event: none\n")
    live = route and registered and installed and lib is not None and py is not None
    out.write("jev: routing spawns in this checkout: {}\n".format("yes" if live else "no"))
    return 0


def ledger_slug(top):
    """Claude Code's auto-memory directory name (hooks/retro-ledger.sh): each of : \\ / . _ -> '-'."""
    return re.sub(r"[:\\/._]", "-", top)


def _local(ts):
    return datetime.datetime.fromisoformat(ts.replace("Z", "+00:00")).astimezone().replace(tzinfo=None)


def _ledger_rows(env, top):
    path = os.path.join(_home(env), ".claude", "projects", ledger_slug(top), "memory", "retro.md")
    rows = []
    for line in (_read(path) or b"").decode("utf-8", "replace").splitlines():
        m = LEDGER_RE.match(line)
        if m:
            rows.append((datetime.datetime.strptime(m.group(1), "%Y-%m-%d %H:%M"), m.group(2).strip(), line))
    return rows


def _idx(model):
    return jev_route.ORDER.index(model) if model in jev_route.ORDER else -1


def cmd_report(top, gd, env, out, registry):
    evs = _events(gd)
    out.write("jev report: {} spawns seen\n".format(len(evs)))
    if not evs:
        return 0
    applied = [e for e in evs if e.get("applied") is True]
    up = sum(1 for e in applied if _idx(e.get("emitted")) > _idx(jev_route.family(e.get("default") or "")))
    out.write("  applied: {} (up {}, down {})\n".format(len(applied), up, len(applied) - up))
    reasons = Counter(str(e.get("reason")) for e in evs if e.get("applied") is not True)
    out.write("  not applied: {}\n".format(", ".join("{} {}".format(r, n) for r, n in sorted(reasons.items())) or "none"))
    confs = [e["confidence"] for e in evs
             if isinstance(e.get("confidence"), (int, float)) and not isinstance(e.get("confidence"), bool)]
    out.write("  model confidence: <0.5: {}, 0.5-0.8: {}, >=0.8: {}\n".format(
        sum(c < 0.5 for c in confs), sum(0.5 <= c < 0.8 for c in confs), sum(c >= 0.8 for c in confs)))
    eff = [e for e in evs if e.get("agent_effort") and e.get("effort_choice")]
    out.write("  effort recommendation differs from the agent file's effort: {} of {}\n".format(
        sum(e["agent_effort"] != e["effort_choice"] for e in eff), len(eff)))
    rows, hits = _ledger_rows(env, top), []
    for e in applied:
        try:
            t = _local(e["ts"]).replace(second=0, microsecond=0)
        except (KeyError, TypeError, ValueError):
            continue
        for when, atype, line in rows:
            if atype == e.get("subagent_type") and datetime.timedelta(0) <= when - t <= datetime.timedelta(minutes=60):
                hits.append((e, line))
    out.write("  retro-ledger failure rows within 60 min after a routed spawn of the same type: {} "
              "(hook blocks and dead tools -- not the agent's report status)\n".format(len(hits)))
    for e, line in hits:
        out.write("    {} {} -> {}: {}\n".format(e.get("ts"), e.get("subagent_type"), e.get("emitted"), line))
    return 0


def main(argv=None, cwd=None, env=None, out=None, registry=None):
    argv = sys.argv[1:] if argv is None else argv
    env = dict(os.environ) if env is None else env
    out = out or sys.stdout
    cmd = (argv[0] if argv else "status").strip().lower()
    handlers = {"on": cmd_on, "off": cmd_off, "status": cmd_status, "report": cmd_report}
    if cmd not in handlers or len(argv) > 1:
        out.write(USAGE)
        return 2
    try:
        top, gd = locate(cwd or os.getcwd())
        return handlers[cmd](top, gd, env, out, registry)
    except (CtlError, OSError) as exc:
        out.write("jev: error: {}\n".format(exc))
        return 1


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: Create `SKILL.md`.** Check 47 applies: no `$` + digit anywhere, and no `$ARGUMENTS`.

```markdown
---
name: jev
description: Switch the optional Jev spawn router on or off for this clone, or show its status or report. Triggers on /jev.
disable-model-invocation: true
argument-hint: on | off | status | report
---

# /jev — optional Jev spawn routing (v4.4.0, Phase 1a)

Run exactly one command, using the word the user typed after `/jev` (no word means `status`), and relay its output verbatim:

    python3 ~/.claude/skills/jev/jev_ctl.py status

(`on`, `off` or `report` in place of `status`.) Never edit `.claude/settings.local.json` or `<git common dir>/jev/config.json` yourself: `jev_ctl.py` writes both, and `off` restores the settings file byte for byte when nobody edited it since `on`.

## What it does

- **On** (per clone): writes `{"model": "jev-1.13.0", "threshold": 0.8, "route": true, "legs": false}` to `<git common dir>/jev/config.json`, registers ONE `PreToolUse` entry (matcher `Agent`) in this checkout's `.claude/settings.local.json`, and excludes that file from git. Another checkout (a worktree) of the same clone needs its own `/jev on`; until then `hooks/model-floor.sh` keeps flooring there.
- **Per spawn** that passes no `model`: TypeSafe's Jev picks a model in ~0.3 s. It applies only at confidence ≥ 0.8, at most one step from the agent file's default (haiku < sonnet < opus < fable), and never below sonnet for `review`/`architect` types. A spawn with no model of its own always leaves with one: Jev's choice, or the project floor when Jev is unsure, slow (2 s), unreachable or keyless. Effort is logged, never applied.
- **Off**: the switch goes off first, so `hooks/model-floor.sh` floors again at once. Then the registration is removed. Events stay for `/jev report`.

## The one rule exception while on

AGENT_TEAM.md's "Typed agents own their `model`; a type without one (general-purpose, built-ins) gets the project default via `hooks/model-floor.sh` unless you pass one" is overridden for spawns Jev routes, within the bounds above: Jev may move a typed agent one step from its own model. A `model` passed in the call is never changed, so a spawn that passes one is never routed.

## What leaves the machine

Only for a spawn Jev routes: the agent type, description and prompt, with secrets, emails, your username and home paths masked, trimmed to 4,000 characters. A spawn whose text still holds a secret-shaped token is not sent at all. The key (`TYPESAFE_API_KEY`, else `HKCU\Environment`) goes in a header only and is never printed or logged. `<git common dir>/jev/events/` holds decisions and confidences, never the prompt or the key.
```

- [ ] **Step 5: Run.** Expected: `Ran 89 tests … OK`. Then run check 47's scan on the new file: `grep -nE '\$[0-9]|\$\{[0-9]\}|\$ARGUMENTS' user-level-reference/skills/jev/SKILL.md` must print nothing.

- [ ] **Step 6: Bump J-PY** `JPY_WANT=89`. `run-block.sh … v4.4.0 J-PY`: 4 passed.

- [ ] **Step 7: Commit** (`feat(jev): /jev on|off|status|report -- byte-exact settings round trip, refuses a pre-v4.4.0 model-floor (v4.4.0)`). Paths: `user-level-reference/skills/jev/jev_ctl.py user-level-reference/skills/jev/SKILL.md user-level-reference/skills/jev/tests/test_ctl.py scripts/test-hooks.sh`.

---

### Task 9: Check 64 (zero footprint, census) and the docs that name skills

**Files:**
- Modify: `scripts/verify-template-consistency.sh`, inserting check 64 directly after the check 63c `fi` and before the `# Check 43` banner (~:4010 at 3a901fe). Renumber if v4.3.1 took 64.
- Modify: `README.md:21` (skill count and list)
- Modify: `user-level-reference/README.md` (skills table, after the `backlog-board` row ~:90)

**Interfaces:**
- Consumes: `AM_JEV_MARKER='…'` (Task 3), `REG_COMMAND = '…'` (Task 8), `disable-model-invocation: true` (Task 8).

- [ ] **Step 1: Write check 64 with its control:**

```bash
# ---------------------------------------------------------------------------
# Check 64 -- Jev is opt-in per clone and ships no registration (v4.4.0, spec
# D1 "zero footprint when off"). (a) No shipped settings file registers the
# router -- only `/jev on` writes it, into one checkout's settings.local.json.
# (b) /jev can never be model-invoked (the model must not switch egress on).
# (c) The registration jev_ctl.py writes is the spec's literal and contains
# the marker agent-model.sh's am_jev_routing greps for: if those two drift
# apart, model-floor never steps aside for a live router (two emitters) or
# steps aside for a dead one (none).
# ---------------------------------------------------------------------------
note "Check 64: no shipped settings registers the Jev router; /jev is user-invoked only; the registration and the step-aside marker agree"
C64_SPEC_REG='f="$HOME/.claude/skills/jev/jev_route.py"; [ -f "$f" ] && python3 "$f"; exit 0'
c64_scan_settings() { # <settings file> -> prints the file when it registers the router
  grep -lF 'jev_route.py' "$1" 2>/dev/null
}
c64_bad=""
for c64_f in templates/*/.claude/settings.json .claude/settings.json user-level-reference/settings.json; do
  [ -n "$(c64_scan_settings "$c64_f")" ] && c64_bad="$c64_bad $c64_f(registers jev_route.py)"
done
c64_skill=user-level-reference/skills/jev/SKILL.md
grep -qx 'disable-model-invocation: true' "$c64_skill" 2>/dev/null || c64_bad="$c64_bad $c64_skill(no 'disable-model-invocation: true' line)"
c64_marker=$(sed -n "s/^AM_JEV_MARKER='\(.*\)'\$/\1/p" hooks/lib/agent-model.sh | head -1)
c64_reg=$(sed -n "s/^REG_COMMAND = '\(.*\)'\$/\1/p" user-level-reference/skills/jev/jev_ctl.py | head -1)
[ -n "$c64_marker" ] || c64_bad="$c64_bad agent-model.sh(no AM_JEV_MARKER line)"
[ "$c64_reg" = "$C64_SPEC_REG" ] || c64_bad="$c64_bad jev_ctl.py(REG_COMMAND is not the spec literal: '${c64_reg:-<none>}')"
case "$c64_reg" in *"$c64_marker"*) ;; *) c64_bad="$c64_bad REG_COMMAND does not contain AM_JEV_MARKER '$c64_marker'" ;; esac
if [ -z "$c64_bad" ]; then
  ok "check 64: no template, root or user-level settings registers jev_route.py; /jev is disable-model-invocation; REG_COMMAND is the spec literal and contains AM_JEV_MARKER"
else
  ko "check 64:$c64_bad"
fi
# 64c control: a planted registration in a scratch settings copy is flagged,
# and the untouched real template is not.
C64C_TMP=$(mktemp -d 2>/dev/null || mktemp -d -t c64c)
cp templates/general/.claude/settings.json "$C64C_TMP/planted.json"
printf '%s\n' "$C64_SPEC_REG" >> "$C64C_TMP/planted.json"
if [ -n "$(c64_scan_settings "$C64C_TMP/planted.json")" ] && [ -z "$(c64_scan_settings templates/general/.claude/settings.json)" ]; then
  ok "check 64c: control -- a planted router registration is flagged; the real template is not"
else
  ko "check 64c: control failed -- check 64's settings scan is vacuous or over-strict"
fi
rm -rf "$C64C_TMP"
```

- [ ] **Step 2: Run it red first.** In a scratch copy (never in the real tree), change `REG_COMMAND` in `jev_ctl.py`, or rename `AM_JEV_MARKER` in the lib, and check that check 64 fails. Simplest way: run the check 64 lines alone with `c64_reg` overridden. Then run the full consistency script on the real tree: `bash scripts/verify-template-consistency.sh 2>&1 | grep -E 'check 64|ALL CHECKS'`. Expected: the two check-64 PASS lines and `ALL CHECKS PASSED`.

- [ ] **Step 3: Docs.**
  - `README.md:21`: `**9 user-level skills**` → `**10 user-level skills**`, and add `` `/jev` `` after `` `/retro-review` `` in the list. Nothing else on that line changes.
  - `user-level-reference/README.md`: after the `backlog-board` row, add:
    `| `jev` | `/jev on\|off\|status\|report` only | Optional, per clone (default off): routes sub-agent spawns that pass no `model` through TypeSafe's Jev -- one step at most from the agent's default, reviewers never below sonnet, the project floor on any failure. Sends the redacted, trimmed spawn text off the machine while on. Needs python3 and `TYPESAFE_API_KEY` |`
  - Grep `docs/architecture.md`, `README.md` and `user-level-reference/README.md` for other skill counts or lists (`user-level skills`, `9 skills`, `backlog-board`) and update each count that means "user-level skills". The Context Budget `skills` row is Task 10's.

- [ ] **Step 4: Verify.** A full consistency run → `ALL CHECKS PASSED`. `bash -n scripts/verify-template-consistency.sh`.

- [ ] **Step 5: Commit** (`test(consistency): check 64 -- Jev ships no registration, /jev is user-invoked, registration and step-aside marker agree; docs list /jev (v4.4.0)`). Paths: `scripts/verify-template-consistency.sh README.md user-level-reference/README.md` (plus `docs/architecture.md` if Step 3 touched it).

---

### Task 10: Release docs (CHANGELOG, VERSION, marker, measured context tables)

**Files:** `VERSION`; `server/src/template_sync/VERSION` (byte-identical, check 44); `user-level-reference/skills/sync-template/SKILL.md` marker → `v4.4.0`; `CHANGELOG.md`; `README.md` (*The trim pass, measured* table, new column); `docs/architecture.md` (*Context Budget* table, new column and the `skills` row → 10).

- [ ] **Step 1: Measure, never carry forward.** Run `wc -c` on every file feeding the tables at this tip:
  - `templates/*/CLAUDE.md`, `templates/*/.claude/rules/project.md`, `templates/*/.claude/project-instructions.md`, `templates/*/PROJECT_CONTEXT.md`;
  - `user-level-reference/CLAUDE.md`, `user-level-reference/output-styles/pm-report.md`;
  - the on-demand `templates/general/AGENT_TEAM.md`.
  This plan changes none of them, so the injected and bootstrap subtotals should equal v4.3.1's column. If any differs, find out why before writing the column. The `jev` skill is `disable-model-invocation: true`. Write "adds no bytes to the skill listing" only if Task 11's live session confirms `jev` is absent from the listing; otherwise write "not measured".
- [ ] **Step 2: VERSION.** Line 1 `4.4.0`. Line 2: `Optional Jev spawn routing (user-level /jev skill, off by default, per clone) on model-floor's resolution moved to hooks/lib/agent-model.sh; model-floor steps aside only for a router that will run -- hook lib, user-level skill and check changes, no template or server-code change.` Copy the file to `server/src/template_sync/VERSION` and run `cmp` on the pair.
- [ ] **Step 3: SKILL marker.** `<!-- SYNC-TEMPLATE-SKILL-VERSION: v4.4.0 -->`. That is the only change to the sync-template skill body.
- [ ] **Step 4: CHANGELOG.** Add `## v4.4.0 — <tag day>` above v4.3.1, using v4.3.0's section layout (`CHANGELOG.md:3-40` at 3a901fe):
  - **Summary paragraph:** Phase 1a only; Phase 1b out of scope (R-9); merge only on the user's go.
  - **`**Floor reviewed: unchanged — …**`:** "the sync-template skill's sync and migration steps are unchanged; its body changes only its version marker (v4.4.0); the new `hooks/lib/agent-model.sh` and the refactored `hooks/model-floor.sh` reach a consumer through the existing `hooks/**` sync path, and the Jev skill is user-level only."
  - **`### Added`:**
    - the `jev` skill (router, ctl, redactor, 89 Python tests run by J-PY inside **Gate**);
    - `hooks/lib/agent-model.sh` with its CLI line;
    - check 64 + 64c;
    - fixture blocks J-DIFF (zero footprint off: byte-identical to the base release), J-LIB, J-MF, J-PY;
    - the parser matrix's `EXP_JQ_SKIP` + 4.
  - **`### Changed`:**
    - model-floor sources the lib (no behaviour change, J-DIFF);
    - model-floor steps aside only when the router will run (R-2, C1 row 6 amended);
    - the definition census now covers three files. Name the corrected check-63 comment, whose claim was false at v4.3.0.
  - **`### Known limits`:**
    1. under the user-level rule "every spawn names its `model`", Jev routes almost nothing (open question), and where `CLAUDE_CODE_SUBAGENT_MODEL` is set, general-purpose and untyped spawns are left to it (R-4);
    2. per routed spawn: python startup + one bash resolver + ~0.3 s API. Under a machine-wide stall the 5 s hook timeout can kill the router, and then the spawn inherits, since model-floor has stepped aside;
    3. in Phase 0, 12 of 80 runs (15 %) were refused by the residual check, and those spawns get the floor or their own model;
    4. no event rotation;
    5. registration is detected by substring (a permission rule naming `skills/jev/jev_route.py` counts);
    6. `/jev report`'s outcome join is retro-ledger failure rows, not report status (R-6);
    7. effort is logged only;
    8. a consumer whose hooks predate v4.4.0 cannot be switched on (`on` refuses, R-8);
    9. a session started in a subdirectory with its own `.claude/` is not modelled.
  - **`### Downstream migration`:**
    - this repo's live install: copy `user-level-reference/hooks/lib/agent-model.sh` and `user-level-reference/hooks/model-floor.sh` to `~/.claude/hooks/`, and `user-level-reference/skills/jev/` to `~/.claude/skills/jev/` (no `__pycache__`);
    - `verify-user-level-drift.sh` must report 0;
    - consumers get the lib and the new model-floor via `/sync-template`, and nothing else changes for them;
    - Jev stays off until someone runs `/jev on` in a clone; that needs python3 ≥ 3.8 and `TYPESAFE_API_KEY`.
  - **Counts:** consistency measured by one full run at this tip; hook suite and server `<pending gate>` (the controller fills them from Task 11, naming where each was measured); J-PY `89`.
- [ ] **Step 5: Tables.** Add a v4.4.0 column to README's table and architecture's Context Budget, with sums and the `skills` row at `10`. Add one prose sentence per table stating the measured change (expected: "unchanged from v4.3.1; the release adds a user-invoked skill, a hook lib and checks, none of them always-loaded").
- [ ] **Step 6: Verify.** A full consistency run: `ALL CHECKS PASSED`, with checks 43, 44, 56 and 57 included. `cmp VERSION server/src/template_sync/VERSION`.
- [ ] **Step 7: Commit** (`docs(release): v4.4.0 -- CHANGELOG, VERSION, marker, measured context tables`).

---

### Task 11 (controller only): gate, matrix, review, live checks, merge

1. **Gate.** With the user's go (the gate stalls the whole machine), measure spawn latency before and after, then run `bash hooks/run-gate.sh` in the foreground with timeout 600000. Then run the parser matrix (`bash scripts/test-hooks-parser-matrix.sh`, ~90 min). It is mandatory here: model-floor embeds node and Python is a hook language now. Expect `EXP_JQ_SKIP` in band, including J-PY's 4.
2. **Push, PR, and outside review** at the exact sha by mcp-dev-servers. Fixes go on the branch.
3. **L1 live check, no egress: a parallel exit-2 hook still wins over an `updatedInput` rewrite.**
   - In a scratch git repo outside every repo (`$SCRATCH/jev-live`), copy `hooks/model-floor.sh` and `hooks/lib/{json.sh,agent-model.sh}`.
   - Write a `.claude/settings.json` with two `PreToolUse` entries on matcher `Agent`: model-floor (the template wrapper) and `echo "LIVE-DENY exit-2 probe" >&2; exit 2`.
   - Run `claude -p "Use the Agent tool exactly once: subagent_type Plan, NO model parameter, prompt 'Reply with the single word ok.' Then print the tool result verbatim." --output-format json` from that directory, as `cd <dir> && claude -p …`, one command after the `cd`.
   - Expect: the tool result carries `LIVE-DENY`, and no `subagents/` transcript is created for that session under `~/.claude/projects/<slug>/`.
   - Remove the deny entry and re-run. Expect: the subagent transcript's `message.model` is `claude-sonnet-*` (the floor). This shows that `updatedInput` without `permissionDecision` applies, and that exit 2 beats it.
4. **Merge only on the user's explicit go** (spec status line). Merge from the gated worktree, fill `<pending gate>`, tag, release, and do the live install per Downstream migration. `verify-user-level-drift.sh` must report 0.
5. **L2 opt-in live smoke**, which costs at most two real API calls. Run it only if the user says so.
   - In `$SCRATCH/jev-live` (with no deny hook), run `python3 ~/.claude/skills/jev/jev_ctl.py on`. Save a copy of `settings.local.json`'s pre-on state first; it is absent here.
   - Spawn exactly as in L1, with Plan and no `model`.
   - Check:
     - (a) one event file in `.git/jev/events/` with a reason from `REASONS`;
     - (b) `grep -c "Reply with the single word"` on it is 0, and the key is absent;
     - (c) the subagent transcript's `message.model` matches the event's `emitted`.
   - Then add the exit-2 entry to `.claude/settings.json` and spawn once more. Expect the block (exit 2 wins over the router).
   - Remove the entry, run `jev_ctl.py off`, and confirm `settings.local.json` is gone, matching its pre-on absence.
   - Also run `jev_ctl.py status` before off and confirm it shows no key.
   - If a session's skill listing can be inspected, record whether `jev` is listed (Task 10's claim).
6. **Memory and board.** Update the project memory and the backlog board with the release state.

## Out of scope (Phase 1b and later)

- `/jev on legs`, the `Bash` registration on `hooks/run-gate.sh`, `needed` predictions per extra leg, and the miss report against the per-leg exit codes (spec "Phase 1b"; R-9).
- Acting on leg predictions; report-quality questions (claims_done, shows_evidence); session-model hints (spec Non-goals).
- Event rotation; a SubagentStop hook to record report status for an honest outcome join (R-6).

## Spec coverage (self-review)

| Spec item | Task |
|---|---|
| D1 default off, per clone, zero footprint | 1 (J-DIFF), 6 (`run` off path), 7 (`off`/unregistered E2E), 9 (check 64) |
| D2 user-level skill, script bundled, `disable-model-invocation` | 4-8; R-3 for the lib |
| D3 allowlisted fields, masking, trim, fail-closed egress | 4, 5 (`build_state`), 6 (`egress-refused`) |
| D4 act at confidence ≥ 0.8 | 5, 6 (config threshold) |
| D5 one step, reviewer floor, explicit never overridden | 5, 6, 7 |
| D6 effort logged only | 6 (event fields), 8 (report) |
| Switch: config, registration literal, exclude, off, status, report | 8 |
| Rule-exception statement | 8 (SKILL.md) |
| Step 2: resolution reused, floor applied while on | 2, 3, 6 (R-1) |
| Steps 4-5: key (env, winreg), header only, 2 s, pinned model, Phase 0 questions | 5, 6, 7 |
| Step 6: `updatedInput` with no `permissionDecision`; exit-2 precedence | 5 (shape), 11 (L1 live) |
| Step 7: failure → default (floor class: the floor) | 6, 7 |
| Step 8: event file, never state or key | 6, 7 |
| Testing: the 15 redactor tests, stubbed HTTP, round trip, status, live | 4, 6-8, 11 |
