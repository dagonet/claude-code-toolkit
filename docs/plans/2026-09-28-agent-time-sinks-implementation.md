# Agent time sinks (v4.3.0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop agents paying for test runs that prove nothing new, stop the budget brake destroying finished work, refuse the command shapes that hang unattended agents, and make every sub-agent spawn without a model run on a cheap default instead of the orchestrator's model.

**Architecture:** Two existing gate hooks gain opt-in keys (`**Test paths**`, `**Gate extra**`); the budget hook exempts commits; two new advisory PreToolUse hooks (`deny-hang-shapes.sh` on Bash, `model-floor.sh` on Agent) ship in all six variants and at user level; one handbook line and two prose lines change. With every new key unset, behaviour equals v4.2.0 except the two new hooks.

**Tech Stack:** bash (Git Bash on Windows), `hooks/lib/json.sh` (node → python3 → jq), `hooks/lib/git-cmd.sh`.

**Spec:** `docs/plans/2026-09-28-agent-time-sinks-design.md` (Parts A1–A3, B1–B2, C1–C2). Read it first.

## Global Constraints

- Branch `feat/agent-time-sinks`, worktree `G:/git/.worktrees/claude-code-toolkit/agent-time-sinks` (based on main d95cf57 = v4.2.0). Nothing lands on `main` until merged by the user's authorisation.
- Every file LF. Edit/Write tools only; files with non-ASCII (CHANGELOG, README, AGENT_TEAM, architecture, user-level CLAUDE.md) never through PowerShell.
- `git -C <worktree> add <explicit paths>` and `git -C <worktree> commit -F <file outside the repo>` as separate calls (timeout 600000; the pre-commit hook runs the full consistency script). Never `add -A`, amend, push, stash. Implementers never spawn subagents.
- Byte-identical across all six variants: every hook script (root `hooks/`), `AGENT_TEAM.md` (cap 20,480 B, check 35). Edit `templates/general/` first, then `cp` to the other five.
- New root hooks are MIRRORED to `user-level-reference/hooks/` (byte-identical, check 21) and registered in `user-level-reference/settings.json` — both new hooks are machine-level concerns.
- New hook registrations in `templates/*/.claude/settings.json` use `${CLAUDE_PROJECT_DIR:-.}/hooks/<name>.sh` (check 24) and the **silent advisory wrapper** `f="${CLAUDE_PROJECT_DIR:-.}/hooks/<name>.sh"; [ -f "$f" ] || exit 0; bash "$f"` (a missing script prints nothing — the context-mode lesson); user level: `f="$HOME/.claude/hooks/<name>.sh"; [ -f "$f" ] || exit 0; bash "$f"`.
- Advisory polarity for both new hooks: missing lib, no JSON parser, invalid payload, any doubt → exit 0 with no output.
- Exact literals: keys `**Test paths**`, `**Gate extra**`, `**Subagent default model**`; model aliases `haiku|sonnet|opus|fable`; default `sonnet`; pre-commit record field `test_sha256`, `env`; skip path literal `test-paths-skip`; artifact fields `reused_test`, `legs`.
- Full `scripts/test-hooks.sh` runs take ~10 min and load a shared machine: implementers run only the NEW fixture blocks (a harness extracting them, like v4.2.0's) plus `bash -n`; the full suite runs at the release gate. Each new fixture block starts with a header line `# ---- v4.3.0 <part>:` and ends with a line `# ---- end v4.3.0 <part>` so a harness can extract it.

## Plan-level refinements of the spec (controller rulings, flagged for the user)

- **R-A (A2 soundness):** reuse is only sound if the Gate is exactly the Test plus the extra legs. When `**Gate extra**` is set, run-gate requires `**Gate**` to equal `<**Test**> && <**Gate extra**>` after whitespace normalisation; otherwise it prints one WARN line, ignores `**Gate extra**` and runs the full Gate (fail-closed). With that invariant, run-gate always runs Test and each extra leg as separate steps, so per-leg results exist whether or not Test is reused.
- **R-B (B1 cd shape):** the merge guard itself requires `cd <gated worktree> && gh pr merge …` (one command after `cd`); the observed hang was `cd <path>; sed …; for …`. The hook refuses a leading `cd <dir>` only when followed by **two or more** commands; `cd <dir> && <one command>` stays allowed.
- **R-C (A1 fail-closed path set):** at PreToolUse time a `git add x && git commit` has not staged `x` yet, so staged paths alone would skip tests wrongly. The skip decision uses `git status --porcelain --untracked-files=all -- <pathspecs>` (staged + unstaged + untracked): any hit → run.

## Review Focus

1. **A `git add … && git commit …` in ONE command** — the index is not yet updated when the hook runs; a docs-plus-code change must still run tests (R-C). Task 1 fixture.
2. **A glob pathspec** (`**Test paths**: *.py src/`) — the shell must not expand it against the hook's cwd. Task 1 uses `set -f`; fixture with a glob.
3. **A stale or foreign pre-commit record** — a record from a changed Test line, a changed environment, older than 24 h, or with `rc` ≠ 0 / `path` ≠ `test` must never be reused. Task 2 fixtures.
4. **`cd <worktree> && gh pr merge 171`** and `git commit -m "$(cat <<'EOF' …)"` must stay allowed (the toolkit's own documented shapes). Task 4 fixtures.
5. **A spawn whose `tool_input` has unknown extra fields** — `updatedInput` must carry every original field unchanged, only `model` added. Task 5 fixture compares all keys.

---

### Task 1: `**Test paths**` in `hooks/pre-commit-test.sh` (A1)

**Files:**
- Modify: `hooks/pre-commit-test.sh` (insert after `PCT_ARTIFACT_BASE="$REPO_PATH"`, ~:350, before the `**Test**` extraction ~:366); copy to `user-level-reference/hooks/pre-commit-test.sh` (byte-identical, check 21)
- Modify: `templates/*/PROJECT_CONTEXT.md` (six files: one documentation bullet each, below the `**Gate**` bullet)
- Test: `scripts/test-hooks.sh` (new block before the final tally ~:7236)

**Interfaces:** Produces the pct_note path literal `test-paths-skip` (never reusable by Task 2).

- [ ] **Step 1: Write the failing fixtures** (insert before the final-tally `echo "----…` line; use existing `mkrepo`, `mkjson`, `pass`/`fail`, `$ROOT`):

```bash
# ---- v4.3.0 A1: **Test paths** (opt-in docs-only skip) ----
TPH=hooks/pre-commit-test.sh
tp_repo() { # <name> <test-paths-line-or-empty> -> repo whose Test prints a marker
  r=$(mkrepo "$1" main)
  printf '#!/usr/bin/env bash\necho TP-SUITE-RAN\nexit 0\n' > "$r/tc.sh"
  { printf '# ctx\n\n- **Test**: `bash tc.sh`\n- **Gate**: `bash tc.sh`\n'; [ -n "$2" ] && printf -- '- **Test paths**: %s\n' "$2"; } > "$r/PROJECT_CONTEXT.md"
  mkdir -p "$r/src" "$r/docs"; echo "$r"
}
tp_run() { printf '%s' "$(mkjson Bash "$2" "$1")" | bash "$ROOT/$TPH" 2>&1; }
tp_expect() { # <label> <want: RAN|SKIP> <output>
  got=SKIP; printf '%s' "$3" | grep -q TP-SUITE-RAN && got=RAN
  if [ "$got" = "$2" ]; then printf 'PASS  %-42s (%s)\n' "$1" "$got"; pass=$((pass + 1))
  else printf 'FAIL  %-42s (want %s, got %s)\n' "$1" "$2" "$got"; fail=$((fail + 1)); fi
}
R=$(tp_repo tp_unset ""); echo d > "$R/docs/a.md"
tp_expect "A1: key unset -> tests run" RAN "$(tp_run "$R" 'git commit -m x')"
R=$(tp_repo tp_docs "src/"); echo d > "$R/docs/a.md"
tp_expect "A1: docs-only change -> skipped" SKIP "$(tp_run "$R" 'git commit -m x')"
R=$(tp_repo tp_code "src/"); echo c > "$R/src/a.c"
tp_expect "A1: code change -> tests run" RAN "$(tp_run "$R" 'git commit -m x')"
R=$(tp_repo tp_addcommit "src/"); echo c > "$R/src/b.c"; echo d > "$R/docs/b.md"
tp_expect "A1: add&&commit, code unstaged -> run (R-C)" RAN "$(tp_run "$R" 'git add docs/b.md && git commit -m x')"
R=$(tp_repo tp_glob "*.c"); echo c > "$R/src/g.c"; touch "$R/zz.c"
tp_expect "A1: glob pathspec not shell-expanded" RAN "$(tp_run "$R" 'git commit -m x')"
R=$(tp_repo tp_ph "{{TEST_PATHS}}"); echo d > "$R/docs/a.md"
tp_expect "A1: placeholder -> treated unset" RAN "$(tp_run "$R" 'git commit -m x')"
R=$(tp_repo tp_del "src/"); git -C "$R" rm -q seed.txt >/dev/null 2>&1; echo c > "$R/src/k.c"; git -C "$R" add -A >/dev/null 2>&1; git -C "$R" commit -q -m k >/dev/null 2>&1; git -C "$R" rm -q src/k.c >/dev/null 2>&1
tp_expect "A1: deletion under src/ -> run" RAN "$(tp_run "$R" 'git commit -m x')"
# ---- end v4.3.0 A1
```

- [ ] **Step 2: Run to verify the skip cases fail** — extract the block with a harness (`awk '/^# ---- v4.3.0 A1:/{f=1} f{print} /^# ---- end v4.3.0 A1/{exit}' scripts/test-hooks.sh`, run with `ROOT`, `TMPROOT=$(mktemp -d)`, `pass=0 fail=0`, and the suite's `mkrepo`/`mkjson`/`jesc` definitions sourced the same way). Expected: `A1: docs-only change -> skipped` FAILs (got RAN); the RAN cases PASS.

- [ ] **Step 3: Implement** — insert after `PCT_ARTIFACT_BASE="$REPO_PATH"`:

```bash
# v4.3.0 A1 -- **Test paths** (opt-in). Unset, empty or an unfilled placeholder
# = test everything (today). When set: skip the Test line only if NO changed
# path -- staged, unstaged or untracked (R-C: `git add x && git commit` has not
# staged x yet when this hook runs) -- matches the pathspecs. set -f keeps the
# shell from expanding a glob pathspec against the cwd. git failing to
# evaluate the pathspecs falls through to the test run (fail-closed).
TEST_PATHS=$(grep -E "${GC_KEY_PRE}\*\*Test paths\*\*:" "$REPO_PATH/PROJECT_CONTEXT.md" 2>/dev/null | sed -E "s/${GC_KEY_PRE}\\*\\*Test paths\\*\\*:[[:space:]]*//;s/[[:space:]]*\$//;s/^\`//;s/\`\$//" | head -1)
case "$TEST_PATHS" in *\{\{*\}\}*) TEST_PATHS="" ;; esac
if [ -n "$TEST_PATHS" ]; then
  set -f
  # shellcheck disable=SC2086 # word-splitting the pathspec list is intended
  if _tp_hits=$(git -C "$REPO_PATH" status --porcelain --untracked-files=all -- $TEST_PATHS 2>/dev/null); then
    set +f
    if [ -z "$_tp_hits" ]; then
      echo "pre-commit-test: no changed path matches **Test paths** ($TEST_PATHS) -- tests skipped for this commit; the merge gate still runs in full" >&2
      pct_note test-paths-skip 0
      exit 0
    fi
  fi
  set +f
fi
```

- [ ] **Step 4: Document the key** in each `templates/*/PROJECT_CONTEXT.md`, directly below the `**Gate**` bullet, exactly:
`- **Test paths**: (optional; unset = every commit runs **Test**) space-separated git pathspecs of code a test could exercise -- a commit touching none of them skips **Test** (the merge gate still runs in full)`
Keep each file's own other lines untouched.

- [ ] **Step 5: Verify** — harness: all seven A1 rows PASS. `bash -n < hooks/pre-commit-test.sh`. `cp hooks/pre-commit-test.sh user-level-reference/hooks/pre-commit-test.sh`; `cmp` them.

- [ ] **Step 6: Commit** (`feat(hooks): **Test paths** -- opt-in docs-only skip in pre-commit-test (A1)`), paths: `hooks/pre-commit-test.sh user-level-reference/hooks/pre-commit-test.sh templates/*/PROJECT_CONTEXT.md scripts/test-hooks.sh`.

---

### Task 2: Pass record fields + `**Gate extra**` reuse and per-leg results (A2)

**Files:**
- Modify: `hooks/pre-commit-test.sh` `pct_note` (~:125-197): add `test_sha256` and `env` to the `last-precommit.<tree>.json` printf; copy to the user-level mirror
- Modify: `hooks/run-gate.sh` (after `GATE_CMD` validation ~:261; the run ~:367; the artifact printf ~:454); copy to the user-level mirror
- Modify: `templates/*/PROJECT_CONTEXT.md` (doc bullet), root `PROJECT_CONTEXT.md` (this repo opts in)
- Test: `scripts/test-hooks.sh`

**Interfaces:** Consumes `test-paths-skip` (never reused). Produces artifact fields `reused_test` (string, empty when not reused) and `legs` (JSON array of `{"sha256","rc","elapsed_s"}`).

- [ ] **Step 1: Failing fixtures** (`# ---- v4.3.0 A2:` … `# ---- end v4.3.0 A2`), each in its own `mkrepo`, Test = `bash t.sh` (echoes `A2-TEST-RAN`), extra leg = `bash x.sh` (echoes `A2-EXTRA-RAN`), `**Gate**: `bash t.sh && bash x.sh``, `**Gate extra**: `bash x.sh``; commit via `pre-commit-test.sh` first (payload `mkjson Bash 'git commit -m x' "$R"`, then really `git -C "$R" commit`), then run `bash "$ROOT/hooks/run-gate.sh"` inside the repo and inspect stdout/stderr and the newest `last-pass.*.json` under `$(git -C "$R" rev-parse --path-format=absolute --git-common-dir)/gate`:
  1. matching record → output contains `A2-EXTRA-RAN`, NOT `A2-TEST-RAN`, artifact `"reused_test":"last-precommit.` and one leg with `"rc":0`;
  2. Test line changed after the commit (edit `**Test**` to `bash t.sh ` + trailing arg) → NOT reused (`A2-TEST-RAN` present) — and because Gate ≠ Test && extra now, the WARN line appears and the full Gate runs;
  3. record `rc` ≠ 0 (hand-edit the record to `"rc":1`) → not reused;
  4. record older than 24 h (`touch -d '25 hours ago'` the record) → not reused;
  5. record `env` differs (hand-edit the record's `env` to `x`) → not reused;
  6. `**Gate extra**` unset → full Gate, artifact has `"legs":[]` and `"reused_test":""`;
  7. extra leg fails (`x.sh` exits 1) → run-gate exits non-zero, no new artifact.

- [ ] **Step 2: Run the block — expect FAILs on rows 1 and 6** (no reuse and no new fields yet).

- [ ] **Step 3: pct_note** — when `$1 = test` and `$2 = 0`, compute `_pn_tsha=$(printf '%s' "$TEST_CMD" | gc_sha256)` (use the existing sha256 helper in `hooks/lib/git-cmd.sh`; if its name differs, use that one) and `_pn_env=$(gc_gate_env "$PCT_ARTIFACT_BASE" 2>/dev/null)`; otherwise both empty. Append `,"test_sha256":"%s","env":"%s"` to the `last-precommit.<tree>.json` printf with those two values. Nothing else in pct_note changes.

- [ ] **Step 4: run-gate** — after `GATE_CMD` is validated:

```bash
# v4.3.0 A2 -- **Gate extra** (opt-in). Sound only if Gate == Test && Gate extra
# (R-A); otherwise ignore it and run the full Gate exactly as before.
rg_field() { grep -E "${GC_KEY_PRE}\*\*$1\*\*:" "$REPO_TOP/PROJECT_CONTEXT.md" 2>/dev/null | sed -E "s/${GC_KEY_PRE}\\*\\*$1\\*\\*:[[:space:]]*//;s/[[:space:]]*\$//;s/^\`//;s/\`\$//" | head -1; }
rg_norm() { tr -s ' \t' '  ' | sed 's/^ //;s/ $//'; }
GATE_EXTRA=$(rg_field 'Gate extra'); RG_TEST=$(rg_field 'Test')
case "$GATE_EXTRA$RG_TEST" in *\{\{*\}\}*) GATE_EXTRA="" ;; esac
if [ -n "$GATE_EXTRA" ] && [ "$(printf '%s' "$GATE_CMD" | rg_norm)" != "$(printf '%s && %s' "$RG_TEST" "$GATE_EXTRA" | rg_norm)" ]; then
  echo "run-gate: WARN **Gate extra** is set but **Gate** is not exactly '<Test> && <Gate extra>' -- ignoring **Gate extra**, running the full Gate" >&2
  GATE_EXTRA=""
fi
```

Then compute the tree hash and `ENV_HASH`/`ENV_DETAIL` BEFORE the run (move or duplicate the existing computations; keep their values identical to what the artifact uses). Reuse decision (only when `GATE_EXTRA` non-empty):

```bash
REUSED=""
RG_REC="$ARTIFACT_DIR/last-precommit.$TREE_HASH.json"
if [ -n "$GATE_EXTRA" ] && [ -f "$RG_REC" ] && [ -n "$ENV_HASH" ] && ! printf '%s' "$ENV_DETAIL" | grep -q '=absent'; then
  rg_rec() { grep -o "\"$1\":\"[^\"]*\"" "$RG_REC" | head -1 | sed "s/\"$1\":\"//;s/\"\$//"; }
  rg_age=$(( $(date +%s) - $(stat -c %Y "$RG_REC" 2>/dev/null || stat -f %m "$RG_REC" 2>/dev/null || echo 0) ))
  if [ "$(rg_rec path)" = test ] && grep -q '"rc":0,' "$RG_REC" \
     && [ "$(rg_rec test_sha256)" = "$(printf '%s' "$RG_TEST" | gc_sha256_rg)" ] \
     && [ "$(rg_rec env)" = "$ENV_HASH" ] && [ "$rg_age" -le "$GC_GATE_PRUNE_S" ]; then
    REUSED=$(basename "$RG_REC")
  fi
fi
```

(`gc_sha256_rg`: run-gate is standalone — add a local sha256 helper using the same backend order `hooks/lib/git-cmd.sh`'s helper uses; the consistency script may already assert run-gate's duplicated constants — follow that pattern.) Freshness: tree and env equality are required, so the merge gate's 3600 s / 24 h rule reduces to age ≤ `GC_GATE_PRUNE_S` (24 h).

Run section: when `GATE_EXTRA` is empty → run `$GATE_CMD` exactly as today, `LEGS_JSON="[]"`. Otherwise: if `REUSED` is empty run `bash -c "$RG_TEST"` (fail → exit as the Gate would), then run each extra leg in order with `bash -c`, recording `{"sha256":…,"rc":…,"elapsed_s":…}`, stopping at the first failure. Legs = `GATE_EXTRA` split on ` && ` ONLY when the value contains none of `'`, `"`, `$(`, `` ` ``, `(`, `<<`; otherwise the whole value is one leg. On success echo `run-gate: Test legs reused from $REUSED` when reused. Artifact printf: append `,"reused_test":"%s","legs":%s` with `$REUSED` and `$LEGS_JSON`. Keep `RUN_GATE_ACTIVE=1` exported around every leg run, as today.

- [ ] **Step 5: Keys** — templates/*/PROJECT_CONTEXT.md, below the `**Test paths**` bullet:
`- **Gate extra**: (optional) the Gate legs beyond **Test**, when **Gate** is exactly \`<Test> && <Gate extra>\` -- lets the merge gate reuse a passing commit-time **Test** run for the same content`
Root `PROJECT_CONTEXT.md`, below its `**Gate**` line: `- **Gate extra**: \`bash scripts/test-hooks.sh && bash scripts/test-server.sh\`` (Gate = consistency && test-hooks && test-server; Test = consistency → R-A holds).

- [ ] **Step 6: Verify** — A2 block all PASS; `bash -n` both hooks; mirror `cp` + `cmp` for both. Commit (`feat(hooks): **Gate extra** -- run-gate reuses a passing commit-time Test run; per-leg results (A2)`).

---

### Task 3: Commits pass the budget brake (A3)

**Files:** Modify `hooks/agent-budget-warn.sh` (block branch ~:117-130). Project-only (HOOKS_NO_MIRROR) — no mirror. Test: `scripts/test-hooks.sh`.

The hook is parser-free by construction (header :21-27) — keep it so.

- [ ] **Step 1: Failing fixtures** (`# ---- v4.3.0 A3:` … `# ---- end v4.3.0 A3`): drive the counter to exactly `BLOCK_AT` (120) for one `agent_id` using the same mechanism the existing budget fixtures use (find them with `grep -n agent-budget-warn scripts/test-hooks.sh`), then send the 120th call as (a) `Bash` `git commit -m x` → expect exit 0 and the budget text on stderr; (b) `Bash` `git -C /x commit -m y` → exit 0; (c) `Bash` `git push origin f` → exit 2; (d) `Read` → exit 2.
- [ ] **Step 2: Run — (a)/(b) FAIL** (currently exit 2).
- [ ] **Step 3: Implement** — at the top of the block branch, before `exit 2`:

```bash
# v4.3.0 A3 -- a commit is the one call worth allowing at budget exhaustion:
# hooks run in parallel, so blocking it after pre-commit-test ran wastes the
# run AND loses the work. Parser-free: a raw match on the payload. A false
# positive lets one non-commit call through once -- the brake still fires on
# every other call.
if printf '%s' "$INPUT" | grep -Eq '"tool_name":"(Bash|PowerShell)"' \
   && printf '%s' "$INPUT" | grep -Eq '"command":"[^"]*\bgit\b([[:space:]]+-[^[:space:]"]+([[:space:]]+[^-[:space:]"][^[:space:]"]*)?)*[[:space:]]+commit\b'; then
  log_event commit-allowed
  echo "BUDGET: $N tool calls -- this commit is allowed so the work is saved; every other call stays blocked. Report and stop after it." >&2
  exit 0
fi
```

(Use the hook's actual stdin variable name — `INPUT` per the research; confirm.)
- [ ] **Step 4: Verify** — A3 rows PASS; existing budget fixtures still PASS (run their block too). Commit (`feat(hooks): budget brake lets a commit through (A3)`).

---

### Task 4: `hooks/deny-hang-shapes.sh` (B1)

**Files:** Create `hooks/deny-hang-shapes.sh`; copy to `user-level-reference/hooks/`; register in all six `templates/*/.claude/settings.json` (a new `"matcher": "Bash"` entry, silent wrapper) and in `user-level-reference/settings.json` PreToolUse (`f="$HOME/.claude/hooks/deny-hang-shapes.sh"; [ -f "$f" ] || exit 0; bash "$f"`) and in this repo's root `.claude/settings.json` if it registers the template hooks (check how `no-push-main.sh` is registered there and mirror that). Test: `scripts/test-hooks.sh`.

- [ ] **Step 1: Failing fixtures** (`# ---- v4.3.0 B1:` … `# ---- end v4.3.0 B1`) with `check "<label>" hooks/deny-hang-shapes.sh <exit> "$(mkjson Bash '<cmd>' "$TMPROOT")"`:
  - exit 2: `cat > f.txt <<'EOF'`; `cat <<EOF > f.txt`; `cat <<EOF >> f.txt`; `tee f.txt <<EOF`; `until [ -f m ]; do sleep 5; done`; `while true; do sleep 1; done`; `cd /tmp; sed -i s/a/b/ f; for i in 1 2; do echo $i; done`; `cd /tmp && a && b`
  - exit 0: `git commit -m "$(cat <<'EOF'` (first line of a message heredoc); `python - <<EOF`; `cat <<EOF | sort`; `cat <<EOF >/dev/null`; `cmd 2>&1`; `sleep 5`; `for f in a b; do echo $f; done`; `cd /tmp`; `cd /g/x && gh pr merge 171`; `bash -c 'cd /tmp && a && b'`
  - kill switch: a dir with `.claude/git-guard-off` and a refused shape → exit 0.
- [ ] **Step 2: Run — the exit-2 rows FAIL** (file missing → check reports wrong exit).
- [ ] **Step 3: Implement** `hooks/deny-hang-shapes.sh`:

```bash
#!/usr/bin/env bash
# deny-hang-shapes.sh -- PreToolUse(Bash): refuse three command shapes that
# hung unattended agents (v4.3.0, spec Part B): a heredoc written into a file,
# a sleep wait loop, and a leading `cd` followed by two or more commands (R-B).
# ADVISORY: a missing lib, no JSON parser, an unreadable payload or any doubt
# lets the call through (exit 0). Honours .claude/git-guard-off.
lib="$(dirname "$0")/lib/json.sh"
[ -f "$lib" ] || exit 0
# shellcheck source=lib/json.sh
. "$lib"
DH_JSON=$(cat)
json_have || exit 0
json_valid "$DH_JSON" || exit 0
DH_CWD=$(json_get "$DH_JSON" cwd)
[ -n "$DH_CWD" ] && [ -f "$DH_CWD/.claude/git-guard-off" ] && exit 0
DH_CMD=$(json_get "$DH_JSON" tool_input.command)
[ -n "$DH_CMD" ] || exit 0
_j=$(printf '%s' "$DH_CMD" | cmd_join_continuations) && [ -n "$_j" ] && DH_CMD="$_j"
dh_refuse() { echo "BLOCKED: deny-hang-shapes: $1" >&2; exit 2; }

# 1. A heredoc into a file: the FIRST line holds both the << and a file target.
DH_FIRST=$(printf '%s\n' "$DH_CMD" | head -1)
if printf '%s' "$DH_FIRST" | grep -Eq '<<-?[[:space:]]*["'"'"']?[A-Za-z_]'; then
  DH_T=$(printf '%s' "$DH_FIRST" | sed -E 's#[0-9]*>&[0-9]+##g; s#>+[[:space:]]*/dev/null##g')
  if printf '%s' "$DH_T" | grep -Eq '(^|[;&|[:space:]])cat[[:space:]][^|;&]*>{1,2}[[:space:]]*[^&[:space:]]' \
     || printf '%s' "$DH_T" | grep -Eq '(^|[;&|[:space:]])tee([[:space:]]+-[a-z]+)*[[:space:]]+[^-|;&[:space:]]'; then
    dh_refuse "a heredoc written into a file can hang an unattended agent -- write files with the Write tool."
  fi
fi

# 2. A wait loop.
if printf '%s' "$DH_CMD" | grep -Eq '(^|[;&|[:space:]])(while|until)[[:space:]]' \
   && printf '%s' "$DH_CMD" | grep -Eq '(^|[;&|[:space:]])sleep[[:space:]]' \
   && printf '%s' "$DH_CMD" | grep -Eq '(^|[;&|[:space:]])done([;&|[:space:]]|$)'; then
  dh_refuse "don't poll: run the command you are waiting on in the foreground (Bash timeout up to 600000 ms), or start it with run_in_background and wait for its completion notice; to watch a condition use the Monitor tool."
fi

# 3. A leading cd followed by two or more commands (R-B).
DH_TRIM=$(printf '%s' "$DH_CMD" | sed -E '1s/^[[:space:]]+//')
if printf '%s' "$DH_TRIM" | grep -Eq '^cd[[:space:]]+[^;&|]+[[:space:]]*(&&|;)'; then
  DH_REST=$(printf '%s' "$DH_TRIM" | sed -E '1s/^cd[[:space:]]+[^;&|]+[[:space:]]*(&&|;)//')
  if printf '%s' "$DH_REST" | grep -Eq '(&&|;|\|\|)' || [ "$(printf '%s\n' "$DH_REST" | grep -c .)" -gt 1 ]; then
    dh_refuse "use absolute paths or git -C <dir>, or put the steps in a script file and run bash <path>, instead of a leading cd before several commands."
  fi
fi
exit 0
```

- [ ] **Step 4: Register** as listed under Files (silent wrapper; `${CLAUDE_PROJECT_DIR:-.}` form for templates).
- [ ] **Step 5: Verify** — B1 rows PASS; `bash -n`; `cmp` mirror; run the consistency harness for checks 13/21/21a/24 (`grep -E 'check (13|21|24)|hook mirror|hook-ref|cwd-independent' <full run output>` — one full consistency run is acceptable here, this is the registration task). Commit (`feat(hooks): deny-hang-shapes -- refuse heredoc-into-file, wait loops and multi-command leading cd (B1)`).

---

### Task 5: `hooks/model-floor.sh` (C1)

**Files:** Create `hooks/model-floor.sh`; mirror to `user-level-reference/hooks/`; register on `"matcher": "Agent"` in all six template settings and `user-level-reference/settings.json` (silent wrapper), and the root `.claude/settings.json` if applicable. Document `**Subagent default model**` in `templates/*/PROJECT_CONTEXT.md`. Test: `scripts/test-hooks.sh`.

- [ ] **Step 1: Failing fixtures** (`# ---- v4.3.0 C1:` … `# ---- end v4.3.0 C1`). Build Agent payloads with printf as the existing Agent fixtures do (~:4130) and a temp repo `R` with `R/.claude/agents/typed.md` (`---\nname: typed\nmodel: haiku\n---\n`) and `R/.claude/agents/inh.md` (`model: inherit`). Cases (stdout captured; `HOME` set to a temp dir with no agents):
  1. `general-purpose`, no model → stdout JSON with `updatedInput.model == "sonnet"` and every other `tool_input` key (`subagent_type`, `prompt`, `description`, plus an extra `"zz_unknown":1`) unchanged — compare with the available parser.
  2. explicit `"model":"opus"` → no stdout, exit 0.
  3. `typed` → no stdout.
  4. `inh` → `sonnet`.
  5. `PROJECT_CONTEXT.md` with `- **Subagent default model**: haiku` → `haiku`; with `{{SUBAGENT_DEFAULT_MODEL}}` or `gpt4` → `sonnet`.
  6. `<common git dir>/jev/config.json` = `{"route": true}` → no stdout.
  7. `subagent_type` = `../x` → no stdout (path-unsafe name).
  8. No parser available (reuse the suite's pattern for hiding parsers, or SKIP by name if the suite has none) → no stdout, exit 0.
- [ ] **Step 2: Run — rows 1, 4, 5 FAIL.**
- [ ] **Step 3: Implement** `hooks/model-floor.sh`:

```bash
#!/usr/bin/env bash
# model-floor.sh -- PreToolUse(Agent): a spawn with no explicit model whose type
# has no model of its own (general-purpose, other built-ins, `model: inherit`)
# runs on the project default instead of the orchestrator's model (v4.3.0, spec
# Part C). Never touches an explicit model or a typed agent's own model. Steps
# aside while Jev routing is on (it applies the same floor). ADVISORY: any doubt
# -> exit 0, no output (the spawn inherits, as before v4.3.0).
lib="$(dirname "$0")/lib/json.sh"
[ -f "$lib" ] || exit 0
# shellcheck source=lib/json.sh
. "$lib"
MF_JSON=$(cat)
json_have || exit 0
json_valid "$MF_JSON" || exit 0
[ "$(json_get "$MF_JSON" tool_name)" = "Agent" ] || exit 0
[ -n "$(json_get "$MF_JSON" tool_input.model)" ] && exit 0
MF_TYPE=$(json_get "$MF_JSON" tool_input.subagent_type)
[ -n "$MF_TYPE" ] || MF_TYPE=general-purpose
case "$MF_TYPE" in *[!A-Za-z0-9_.-]*|.*) exit 0 ;; esac
MF_CWD=$(json_get "$MF_JSON" cwd); [ -n "$MF_CWD" ] || MF_CWD=.
MF_ROOT=$(git -C "$MF_CWD" rev-parse --show-toplevel 2>/dev/null) || MF_ROOT="$MF_CWD"
mf_model() { awk 'NR==1&&/^---/{f=1;next} f&&/^---/{exit} f&&/^model:/{sub(/^model:[[:space:]]*/,"");print;exit}' "$1" 2>/dev/null | tr -d '\r'; }
for mf_f in "$MF_ROOT/.claude/agents/$MF_TYPE.md" "$HOME/.claude/agents/$MF_TYPE.md"; do
  [ -f "$mf_f" ] || continue
  case "$(mf_model "$mf_f")" in haiku|sonnet|opus|fable) exit 0 ;; esac
  break
done
MF_GD=$(git -C "$MF_ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
[ -n "$MF_GD" ] && grep -Eq '"route"[[:space:]]*:[[:space:]]*true' "$MF_GD/jev/config.json" 2>/dev/null && exit 0
MF_DEF=$(grep -E '^[-*[:space:]]*\*\*Subagent default model\*\*:' "$MF_ROOT/PROJECT_CONTEXT.md" 2>/dev/null | head -1 | sed -E 's/.*\*\*Subagent default model\*\*:[[:space:]]*//; s/[`[:space:]]//g')
case "$MF_DEF" in haiku|sonnet|opus|fable) ;; *) MF_DEF=sonnet ;; esac
```

Then emit with the parser `json.sh` selected (read `json.sh` for the variable that names it — e.g. `JSON_PARSER` after `json_parser_init`): node → `Object.assign({}, p.tool_input, {model})`; python3 → `ti = dict(p["tool_input"]); ti["model"] = m`; jq → `.tool_input + {model: $m}`; each wrapped as `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","updatedInput":<ti>}}`, the payload fed on stdin, the model as an argument (never interpolated into code). Emission failure → exit 0 with no output. Also print `model-floor: $MF_TYPE had no model -> $MF_DEF` to stderr on success.
- [ ] **Step 4: Register + document** — settings as in Files; `templates/*/PROJECT_CONTEXT.md` below `**Gate extra**`: `- **Subagent default model**: (optional; default \`sonnet\`) the model a sub-agent spawn gets when neither the call nor its agent file sets one -- general-purpose and built-in agents otherwise inherit the orchestrator's (most expensive) model`
- [ ] **Step 5: Verify** — C1 rows PASS (row 8 may SKIP by name); `bash -n`; mirror `cmp`. Commit (`feat(hooks): model-floor -- spawns without a model get the project default, never the orchestrator's (C1)`).

---

### Task 6: Handbook and prose lines (C2, B2)

**Files:** `templates/*/AGENT_TEAM.md` (six, byte-identical), `templates/dotnet/.claude/rules/csharp.md`, `templates/dotnet-maui/.claude/rules/csharp.md` (NOT identical to each other — edit each), `user-level-reference/CLAUDE.md`.

- [ ] **Step 1: AGENT_TEAM.md line 58** — replace `Never pass \`model\` in the Agent call — each agent file owns its own.` with `Typed agents own their \`model\`; a spawn of a type without one (general-purpose, built-ins) gets the project default from \`hooks/model-floor.sh\` unless you pass \`model\`.` Measure `wc -c templates/general/AGENT_TEAM.md`; if > 20,480, shorten line 59 (`- **Aliases only** (…), never a pinned \`claude-*\` id.`) to `- Aliases only, never a pinned \`claude-*\` id.` and re-measure. `cp` to the five variants.
- [ ] **Step 2: csharp.md (both)** — after the line `- Run \`dotnet format\` to ensure \`.editorconfig\` compliance`, add `- Pass \`dotnet format\` a relative path (or none): a forward-slash absolute path checks 0 files and exits 0 -- a vacuous pass`.
- [ ] **Step 3: user-level CLAUDE.md line 14** — change `Write the logic to a script file and run \`bash <path>\`` to `Write the logic to a script file -- with the Write tool, never a heredoc -- and run \`bash <path>\``.
- [ ] **Step 4: Verify** — one full consistency run (checks 7/R4 byte-identity, 35 cap) → ALL CHECKS PASSED; record `wc -c` of the three changed always-loaded/on-demand files. Commit (`docs: model-floor handbook line; dotnet format relative path; Write-tool note (C2, B2)`).

---

### Task 7: Release docs — CHANGELOG, VERSION, counts, context tables

**Files:** `VERSION`, `server/src/template_sync/VERSION` (byte-identical, check 44), `user-level-reference/skills/sync-template/SKILL.md` version marker (→ `v4.3.0`), `CHANGELOG.md`, `README.md` (hook count :48 `15` → `17`; declared-keys list :49 + `**Test paths**`, `**Gate extra**`, `**Subagent default model**`; context table v4.3.0 column), `docs/architecture.md` (Context Budget v4.3.0 column; hooks tree count 15 → 17).

- [ ] **Step 1: Measure** with `wc -c` every file feeding the tables (the user-level CLAUDE.md grew; AGENT_TEAM.md changed; the style row is unchanged) — never carry forward.
- [ ] **Step 2: VERSION** `4.3.0` + one summary line; copy to the server VERSION.
- [ ] **Step 3: CHANGELOG** — `## v4.3.0 — <tag day>` with `### Added` (A1, A2 incl. R-A, A3, B1 incl. R-B, C1), `### Changed` (C2 handbook line, B2 prose), the signed `**Floor reviewed: unchanged — …**` line (check 56; the sync-template skill body changes only its marker), counts as `<pending gate>` for the hook suite and server (the controller fills them from the release gate, naming where each was measured), consistency measured by one full run, and `### Downstream migration` (sync-template brings the hooks and settings; new keys opt-in; copy the two mirrored hooks + the user-level settings entries; drift → 0).
- [ ] **Step 4: Tables** — README + architecture: a v4.3.0 column, sums shown, prose sentence with the measured growth.
- [ ] **Step 5: Verify** — full consistency ALL CHECKS PASSED (checks 43/44/56/57). Commit (`docs(release): v4.3.0 -- CHANGELOG, VERSION, counts, measured context tables`).

---

### Task 8 (controller only)

1. Full gate on the tip (user's go-ahead covers it within the release instruction); parser matrix (new hooks read payloads through the parser layer).
2. Push, PR, outside review by mcp-dev-servers at the exact sha; fixes on the branch.
3. Fill `<pending gate>` from the gate, naming where measured; merge (user authorisation) from the gated worktree; tag; release; live install (copy the two mirrored hooks + updated mirrors; add the two user-level settings entries; drift 0).
4. Live check: a general-purpose spawn without `model` runs on sonnet (inspect its transcript's `message.model`).
