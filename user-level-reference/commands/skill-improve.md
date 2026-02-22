# /skill-improve - Autonomous Skill Improvement Loop

Iteratively improve a skill by running evals, analyzing failures, making targeted changes, and keeping or reverting based on score.

**Usage:** `/skill-improve <skill-name> [--max-iterations N]`

Default: 5 iterations. Stops early if perfect score is reached.

## Autonomy

Do not pause to ask the human if you should continue between iterations. Keep looping until perfect score, max iterations reached, or manually interrupted. If approaching context limits, save state to results.log and stop gracefully.

## Workflow

1. **Parse arguments**
   - Extract skill name from `$ARGUMENTS`
   - Extract `--max-iterations N` if provided (default: 5)
   - Resolve skill path: `~/.claude/skills/<skill-name>/`
   - Verify `SKILL.md` and `evals/evals.json` exist

2. **Snapshot baseline**
   - Create `evals/snapshots/` directory if it doesn't exist
   - Copy `SKILL.md` → `evals/snapshots/v0-SKILL.md`

3. **Run baseline eval**
   - Execute the full `/skill-eval` workflow inline (same logic: run test cases via subagent, grade via grader subagent)
   - Record baseline score (e.g., 7/10)
   - Track which specific expectations failed and their evidence

4. **Improvement loop** (repeat until perfect score or max iterations)

   For iteration N (starting at 1):

   a. **Analyze failures**
      - Read all failed expectations and their grader evidence from the latest eval
      - Identify the most impactful failure to address (one that might fix multiple assertions)

   b. **Select change strategy** (rotate through these to avoid repeating failed approaches)
      1. Add or clarify a rule in the Rules section
      2. Add or improve an example in the Output Format section
      3. Clarify a workflow step
      4. Add a checklist item
      5. Remove an instruction that may be causing over-specification or conflicting guidance

   c. **Make ONE targeted change to SKILL.md**
      - Apply exactly one change based on the selected strategy
      - The change should directly address the identified failure
      - Keep changes minimal and focused

   d. **Save snapshot**
      - Copy current SKILL.md → `evals/snapshots/v<N>-SKILL.md`

   e. **Re-run full eval**
      - Same eval logic as step 3

   f. **Evaluate result**
      - **If score improved**: Keep the change. Log: `v<N>: <score> (+<delta>) KEPT - <description of change>`
      - **If score same or worse**: Revert SKILL.md from the last good snapshot. Log: `v<N>: <score> (<delta>) REVERTED - <description of change>`

   g. **Stuck detection**
      - If the same expectation has failed for 3 consecutive iterations (with different change strategies each time), flag it:
        `⚠️ Potentially bad assertion: "<expectation>" — failed 3 consecutive attempts with different strategies`
      - Skip this assertion in subsequent iterations
      - Include it in the final report for human review

5. **Final report**
   ```
   ## Skill Improvement: <skill-name>

   ### Score Progression
   v0 (baseline): 7/10
   v1: 8/10 (+1) KEPT - Added rule requiring line numbers in findings
   v2: 8/10 (0) REVERTED - Added example for severity categories
   v3: 9/10 (+1) KEPT - Clarified workflow step for security analysis
   ...

   ### Summary
   - Baseline: 7/10 → Final: 9/10
   - Iterations: 5 (2 kept, 2 reverted, 1 flagged)
   - Flagged assertions: 1
     - ⚠️ "includes line numbers for each finding" — may need eval refinement

   ### Changes Made (diff from v0)
   <show the diff between v0-SKILL.md and current SKILL.md>
   ```

6. **Log full results**
   - Append to `evals/results.log`:
     ```
     --- Improve Run: <ISO timestamp> ---
     Baseline: 7/10 → Final: 9/10
     Iterations: 5 (2 kept, 2 reverted, 1 flagged)
     v1: 8/10 (+1) KEPT - Added rule requiring line numbers
     v2: 8/10 (0) REVERTED - Added severity example
     ...
     ```

7. **Present diff for user review**
   - Show the full diff between `evals/snapshots/v0-SKILL.md` and current `SKILL.md`
   - User decides whether to commit — do NOT auto-commit

## Rules

- MUST snapshot before ANY modification
- MUST make exactly ONE change per iteration — no multi-change iterations
- MUST revert if score doesn't improve — never keep a neutral or negative change
- MUST rotate change strategies — do not repeat the same strategy type on consecutive iterations
- MUST use subagents for skill execution and grading (same as /skill-eval)
- MUST NOT modify evals.json — the test cases are fixed reference points
- MUST log every iteration to results.log, including reverted attempts
- MUST stop gracefully if context is getting large — save state before stopping
- If the skill achieves a perfect score, stop immediately and report success
