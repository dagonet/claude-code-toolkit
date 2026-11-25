# Backlog discipline: every change closes its item — design

Status: approved by the user 2026-11-22 19:24 ("I agree to all what you proposed. go ahead!"). Part 1 of the "slim core" project (topic #1 of 2026-11-22). Part 2 is the plugin split (`2026-11-22-slim-core-plugin-split-design.md`), which ships after this.

## 1. Intent

The core of cct is the delivery workflow:
- the orchestrator acts as product owner and keeps the backlog;
- it sizes each piece of work T1-T4;
- the size picks the team.

Keeping the backlog is the one part with no enforcement. In the user's words, from the mm-agents: "finished items left open, no prioritization of new/existing issues - basically the backlog was only cleaned, updated and re-prioritized when I asked for it."

**Today:**
- **Two backlog modes.** A project picks issue mode, where the backlog is the GitHub issues, or file mode, where it is sprint plan files. Tech debt in file mode goes to the orchestrator's personal memory, which no other machine or person sees.
- **`PROJECT_STATE.md`** has a `## Now` block (re-shown after compaction by `now-brief.sh`) and a `## Backlog` block that says "See GitHub Issues".
- **"Maintains/prioritizes the backlog"** is one sentence in `AGENT_TEAM.md`, and nothing checks it.

## 2. Decisions taken with the user

- **Hard block** (user, 19:05): a change that names no backlog item is refused. The user noted that a block at merge alone can be dodged by not merging.
- **Two documents, two releases** (19:05): backlog discipline first, the plugin split second.
- **Proposed in chat and carried here for approval** (my calls, open to correction):
  - the block sits at **opening the pull request**, with the merge as the second line, because the user merges in GitHub's web page, where no hook runs;
  - issue mode requires GitHub's closing keyword;
  - file mode cannot drift more than one change behind;
  - `Item: none` is allowed for T1 and counted;
  - the check does not depend on a configured Gate;
  - the session start shows the backlog debt.

## 3. Goals, non-goals, anti-goals

- **Goals:**
  - finished items close when their change merges, whoever merges it;
  - new items are recorded in one visible place and ranked;
  - the orchestrator sees backlog debt at every session start;
  - grooming is a step of the workflow, not a request.
- **Non-goals:**
  - judging whether the order is *good* (that stays the orchestrator's and the user's call);
  - an open-brain store (it becomes an optional storage plugin later, with the same item shape);
  - changing how issues are written.
- **Anti-goals:**
  - **A block that a missing setting silently turns off.** Today's merge hook exits 0 when no `**Gate**:` is configured; this check must not inherit that.
  - **`Item: none` becoming the default.** It is explicit, T1 only by rule, and counted in every self-review report.
  - **A check that guesses.** When the check cannot tell, it refuses with a message that says exactly what to add.

## 4. The backlog shape (both modes)

Each item has a number, a state (open, in progress, done) and a rank.

- **Issue mode:**
  - item = GitHub issue `#N`;
  - done = closed;
  - rank = a label `priority:1`, `priority:2` or `priority:3`;
  - **untriaged** = open with no priority label.
- **File mode:** `PROJECT_STATE.md` `## Backlog` gets three fixed subsections:

  ```
  ## Backlog
  ### Untriaged
  - B-14 Retry the export on timeout
  ### Ranked
  - B-9 [in progress] Calendar time-zone fix
  - B-12 Import CSV with BOM
  ### Done
  - B-7 Fix login redirect
  ```

  - item = `B-<n>`, numbered upwards and never reused;
  - rank = the order under `### Ranked`, where the top item is next;
  - `### Done` keeps the last 20 items; older ones are dropped.
- **Personal memory is no longer a backlog place:** the Mode Behavior Table rows for tech debt and sprint state point at the backlog.

## 5. The item check (hard block)

New core hook `hooks/backlog-item-check.sh`. It is fail-closed, has its own registration, and runs **before** any Gate lookup, so a project without `**Gate**:` is still covered. One script, two points:

1. **Opening a pull request.**
   - **What it covers:** `mcp__MCP_DOCKER__create_pull_request` (and the other PR-create tools the merge hook already lists for merges) as a direct registration, plus `gh pr create` through the bash and powershell dispatcher tables.
   - **Issue mode:** the PR body must hold a closing keyword (`Closes`, `Fixes` or `Resolves` `#N`), or a line `Item: none`. For `gh pr create`, a body that cannot be read from the command (`--fill`, `--editor`, `--web`) means refuse, with "pass `--body` or `--body-file`".
   - **File mode:** the branch's change against its base must do one of two things.
     - Move at least one `B-<n>` into `### Done` in `PROJECT_STATE.md`. **The change carries its own backlog update**, so merging it, in the browser or anywhere else, closes the item.
     - Or carry a commit with the trailer `Item: none`.
2. **Merging** (second line). On the merge shapes `gate-before-merge.sh` already handles, file mode re-runs the same diff check on the local checkout. Issue mode has no local view of the PR body, so the second line covers file mode only; the docs say so.

**Unreadable or unknown state means refuse.** Examples: no `## Backlog` subsections in file mode, no base ref, or a body that cannot be read. The message names the exact fix, such as the three subsection headings to add. This includes existing projects on their first PR after the update. The release notes say so.

**Escape hatch:** the existing `.claude/git-guard-off` kill switch, as for every git guard. Nothing new.

**`Task source` decides the mode** (`PROJECT_CONTEXT.md`, today `plan-files` or `github-issues`). A missing or unknown value means refuse.

## 6. Grooming as a workflow step

- **Rule.** `AGENT_TEAM.md` (all six variants, byte-identical) gets a "Backlog" block. It holds the shape above and one rule: *before picking the next task, groom*. Grooming means closing finished items, ranking everything untriaged, and re-checking the top three. The sentence "maintains/prioritizes the backlog" points at it.
- **Sprint command.** `skills/sprint` makes grooming its step 1, before any spawn.
- **Session-start line.** `now-brief.sh` widens from compaction-only to every session start, and adds one line after the `## Now` block. It stays advisory.
  - **File mode:** `backlog: <u> untriaged, <p> in progress, top: B-<n> <title>`.
  - **Issue mode:** the same counts from `gh issue list`, time-boxed to 5 s. It is silent when `gh` is missing or slow.
- **Findings go in.** The reviewer and tester report contracts gain a fixed line `Follow-ups: none` or `Follow-ups: <one per line>`. When a returning report has follow-ups, a PostToolUse(`Agent`) note says: "Add these follow-ups to the backlog as untriaged items." This shares the PostToolUse(`Agent`) hook planned in the model-ladder design if that ships first; otherwise it is its own small hook.

## 7. Measurement

The self-review counter gains these counts:
- PRs opened with `Item: none`;
- refusals by this hook, split by mode and reason (no item, unreadable body, missing subsections);
- follow-up notes shown.

All are counts only, under the existing privacy rules.

## 8. Tests

- **`scripts/test-hooks.sh` rows, two-sided for each point:**
  - each mode with an item gives an allow, and without one gives a refusal;
  - `Item: none` gives an allow;
  - an unreadable body or missing subsections gives a refusal with the fix text;
  - no `**Gate**:` configured still gives a refusal;
  - the kill switch gives an allow;
  - a tool that is not a PR creation gives an allow.
- **Fixtures** for the session-start line and the follow-up note.
- **Consistency checks:**
  - the hook is registered for PR creation in `hooks/hooks.json` and in both dispatcher tables;
  - the six `AGENT_TEAM.md` copies carry the Backlog block;
  - the six `PROJECT_STATE.md` templates carry the three subsections.

## 9. Delivery

- **Release:** the next minor after the releases already queued (v6.3.0, model ladder v6.4.0), so v6.5.0 unless the user reorders.
- **Consumers:**
  - template sync brings the `AGENT_TEAM.md` and hook changes;
  - `PROJECT_STATE.md` is project-owned, so its first PR is refused with the fix text, and the release notes tell each project to add the three subsections (file mode) or the priority labels (issue mode) once.
- **Context Budget** column measured at release, as usual.

## 10. Calls made after the builder check

1. **One item = one pull request** (user-approved 19:24). An item that needs several PRs is split into several items when it is ranked. So every PR in file mode moves exactly the item(s) it finishes into `### Done`. A PR naming an item already in Done is refused. No "partial" trailer exists, because it would recreate "finished items left open".
2. **Which diff.**
   - **Head:** the checkout's `HEAD` in the hook's cwd. If the cwd branch differs from the PR's head name, the check refuses.
   - **Base:** the local `origin/<base>`, where base is the tool input's base, or `main` for `gh pr create` without `--base`. A missing ref means refuse, with "fetch first".
   - **No network.**
3. **`Item: none` is accepted from any PR.** The hook cannot see the T-size. "T1 only" is a written rule, and the self-review count is its control.
4. **Mode and item parsing.**
   - **Mode:** `Task source` in the repo root's `PROJECT_CONTEXT.md`. Exactly `plan-files` means file mode; exactly `github-issues` means issue mode. Backticks and spaces are trimmed, and anything else means refuse.
   - **Scope:** the hook is project-only (`run-hook.sh`'s toolkit-project signal), so repos that are not cct projects are untouched.
   - **Issue mode** accepts same-repo `#N` with a closing keyword and does not verify the issue over the network. A cross-repo `owner/repo#N` does not count.
5. **What is covered.**
   - **PR creation:** `mcp__MCP_DOCKER__create_pull_request`, the only PR-create tool in use, plus `gh pr create` in the bash and powershell dispatcher tables.
   - **`gh pr create` bodies:** the body is read only from `--body`/`-b` (a literal) or `--body-file`/`-F` (a file read by the hook). Any other form, including a subshell, means refuse, with "use `--body-file`".
6. **Merge second line.** It uses the same diff check, from the merging checkout. `gate-before-merge` already requires that checkout to be the PR's own (merges from a protected branch are refused), so no fetch is needed. It is a separate registration that runs beside `gate-before-merge.sh`; one merge can get two refusals, each naming its own fix.
7. **Kill switch.** It honours `.claude/git-guard-off` through the same helper in `hooks/lib/git-cmd.sh` the other git guards use.
8. **Session start.**
   - **Registration:** `now-brief.sh` registers for every source (`startup|resume|compact|clear`).
   - **What it shows:** the `## Now` block still only after a compaction, as today; the backlog line on every start.
   - **Issue mode** uses `gh issue list` with a 3 s timeout and is silent on any failure, missing auth included.
9. **Follow-ups note.** It reads only results of `cct:code-reviewer` and `cct:tester`. Built standalone as `hooks/agent-result-notes.sh` (PostToolUse `Agent`, advisory), which the model-ladder step-up note later joins as a second rule. Whichever ships first creates the script.
10. **Counter and version.**
    - **Counter:** the counts in section 7 extend `scripts/self-review-count.py` (shared JSON keys `backlog_item_none`, `backlog_refusals` {mode/reason: n} and `followup_notes`).
    - **Version:** the release takes the next minor after whatever has shipped by then.
11. **This repo is in scope.** The toolkit gates itself and is in file mode, but has no root `PROJECT_STATE.md`. The change adds one, with the three backlog subsections, so this repo's own PRs pass.

### 10a. Changes after the plan challenge (user-approved 2026-11-22 20:04)

These supersede the matching items above where they differ.

- **A. PR bodies.** `gh pr create` bodies are read **only** from `--body-file`/`-F`. A `--body` literal is refused with "use --body-file". Reason: the existing command parser strips quotes and splits inside them, so a literal cannot be read safely.
- **B. Base.**
  - **Where it comes from:** the tool input's base, `--base`/`-B`, else the local `refs/remotes/origin/HEAD`. If that is missing, the check refuses with "pass --base". `main` is never assumed.
  - **Merge shapes:** the merge second line covers only `gh pr merge` and the MCP merge tools. `git merge` on a protected branch is dropped there, because HEAD is the trunk itself and `no-push-main` already blocks the push.
- **C. Pushed state.** HEAD must equal the local `origin/<head>`, else the check refuses with "push first". No network is used.
- **D. Session-start line.** A separate small advisory hook, `backlog-brief.sh`, runs on every session start. `now-brief.sh` and its fixtures stay untouched.
- **E. Grooming lands first.**
  - **Order:** ranking and new items reach the trunk before helpers start, so the item ids exist in base.
  - **Exempt PRs:** a PR whose change touches only `PROJECT_STATE.md` needs no item.
  - **First PR after the update:** the base has no subsections yet, so the PR that adds them is accepted through `Item: none`. The refusal text says so.
  - **Sync PRs:** they carry `Item: none` (commit trailer plus a body line). `skills/sync-template` is updated to do that and to use `--body-file`.
- **F. Reviewer follow-ups.** The reviewer's strict `clean` stays, with an optional `Follow-ups:` block after it. The tester is `pipeline: notify`, so only the reviewer verdict changes.
- **This repo.** Project-class plugin hooks skip a repo without `.claude/template-manifest.json`, and the toolkit root has none. So `backlog-item-check` is also registered in the root `.claude/settings.json`, the same way the root registers its other gates.
- **Counter.** `Item: none` is counted from PR-create inputs **and** commit messages, in main and subagent transcripts. Follow-ups are counted from reviewer/tester result text, not from the note.

## 11. Left to the builder

- Exact regexes for the closing keyword and the `B-<n>` move, and how "moved into Done" is read from the diff.
- Hook JSON output shapes and message wording, within "name the exact fix".
- Whether the PostToolUse(`Agent`) note shares a script with the model-ladder hook, depending on release order.
