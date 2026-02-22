# /challenge - Challenge a Plan or Design

Challenge the current plan, approach, or design with two structured passes. Catches over-engineering, missing requirements, YAGNI violations, and implementation flaws early.

## Arguments
- `$ARGUMENTS` - (Optional) Description of what to challenge. If omitted, challenge the current plan or approach in the conversation context.

## Workflow

1. **Identify the target**
   - If `$ARGUMENTS` is provided, use it as the challenge target
   - If omitted, identify the most recent plan, design, or proposed approach in the conversation
   - If no clear target exists, ASK the user what to challenge

2. **Attempt Architect delegation**
   - If an architect agent is available (team context with AGENT_TEAM.md), spawn the architect to perform both challenges
   - If no architect is available (solo session), perform both challenges directly

3. **Challenge 1 — Scope & Necessity**
   - Is every component/feature actually needed? (YAGNI check)
   - Are there simpler approaches that were dismissed too quickly?
   - Are edge cases identified but deferred appropriately?
   - Does the design solve the stated problem without gold-plating?
   - Is the tier assignment (if applicable) correct for the scope?
   - Could any pieces be cut without losing the core value?

4. **Challenge 2 — Correctness & Completeness**
   - Does the plan match the stated requirements faithfully?
   - Are there missing steps, untested paths, or incorrect assumptions?
   - Are error handling and validation covered at every layer?
   - Will the proposed changes pass CI (formatting, linting, type checks)?
   - Are there batches or tasks that should be cut or reordered?
   - Does the team configuration (if applicable) match the assigned tier?

5. **Present results**
   - For each challenge pass, output a numbered list of:
     - Changes made (cuts, additions, corrections)
     - Rationale for each change
   - If no changes result from a pass, state: "Challenged — no changes needed"
   - Present the revised plan/approach incorporating all changes

## Rules
- MUST perform exactly two challenge passes — never skip the second
- MUST challenge substance, not style — focus on correctness, scope, and completeness
- MUST preserve the original intent while cutting scope or simplifying
- MUST NOT rubber-stamp — if you can't find issues, look harder at assumptions and edge cases
- If the architect agent is available, MUST delegate to it rather than self-challenging
- After both passes, present the final revised version for user approval
