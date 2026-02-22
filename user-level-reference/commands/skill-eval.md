# /skill-eval - Evaluate a Skill Against Test Cases

Run all test cases for a skill and report pass/fail results. Does not modify the skill.

**Usage:** `/skill-eval <skill-name>`

## Workflow

1. **Resolve skill path**
   - Parse `$ARGUMENTS` as the skill name (e.g., `code-review`)
   - Look for the skill directory at `~/.claude/skills/<skill-name>/`
   - Verify `SKILL.md` exists in that directory
   - Verify `evals/evals.json` exists in that directory
   - If either is missing, report the error and stop

2. **Load test cases**
   - Read `evals/evals.json`
   - Parse the `evals` array — each entry has: `id`, `prompt`, `expected_output`, `expectations`

3. **Run each test case**
   - For each eval in the array:
     a. Read the skill's `SKILL.md` content
     b. Spawn a subagent with this system prompt:
        ```
        You are testing a skill. Follow these instructions exactly as if they were your skill instructions:

        ---
        <contents of SKILL.md>
        ---

        Now respond to the following user request. Produce the output the skill describes.
        Do NOT mention that you are being tested or evaluated.
        ```
     c. Pass the eval's `prompt` as the user message
     d. Capture the subagent's full text output

4. **Grade each test case**
   - For each test case output, spawn a **grader subagent** with this prompt:
     ```
     You are an eval grader. You receive a skill's output and a list of binary expectations.
     For each expectation, determine if the output satisfies it using natural language understanding (not regex).
     Be strict: if the expectation says "contains X" and X is absent, it fails.
     Be fair: minor wording differences are acceptable if the intent is met.

     Return ONLY a JSON array, no other text:
     [{"expectation": "...", "pass": true/false, "evidence": "brief quote or reason"}]
     ```
   - Pass to the grader:
     ```
     ## Skill Output
     <the captured output>

     ## Expectations
     <numbered list of expectations from evals.json>
     ```
   - Parse the grader's JSON response

5. **Aggregate and display results**
   ```
   ## Eval Results: <skill-name>

   | # | Test | Pass Rate | Details |
   |---|------|-----------|---------|
   | 1 | <expected_output summary> | 4/5 (80%) | Failed: "<failed expectation>" |
   | 2 | <expected_output summary> | 5/5 (100%) | All passed |

   **Overall: 9/10 (90%)**
   ```

6. **Log results**
   - Append to `~/.claude/skills/<skill-name>/evals/results.log`:
     ```
     --- Run: <ISO timestamp> ---
     Score: 9/10 (90%)
     #1: 4/5 - Failed: "<expectation>"
     #2: 5/5 - All passed
     ```

## Rules

- MUST NOT modify `SKILL.md` — this command is read-only evaluation
- MUST run ALL test cases, not stop at first failure
- MUST use subagents for both skill execution and grading — do not self-grade
- MUST parse grader output as JSON — if grader returns malformed JSON, mark that test as errored
- MUST append to results.log, never overwrite it
- If `evals/` directory doesn't exist, create it before writing results.log
- Display results in a clean markdown table
