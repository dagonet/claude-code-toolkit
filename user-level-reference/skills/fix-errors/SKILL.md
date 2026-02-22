---
name: fix-errors
description: Parses build errors and fixes them systematically. Triggers on build failures, compilation errors, or when user reports errors.
---

# Fix Errors Skill

Parse error output and fix issues systematically.

## When to Use

This skill auto-activates when:
- Build fails with errors
- User pastes error output
- User mentions "fix errors", "build failed", or "compilation error"
- User asks to resolve CS#### error codes

## Workflow

1. **Get error information**
   - If error text provided:
     - Call `extract_json(text, schema)` with error schema
   - If path provided:
     - Call `build_and_extract_errors(project_or_sln)`
   - If empty:
     - Call `map_dotnet_structure(root)` to find solution
     - Call `build_and_extract_errors` on the solution

2. **Parse and categorize errors**
   ```json
   {
     "errors": [
       {"code": "CS0246", "message": "...", "file": "...", "line": N}
     ],
     "warnings": [...]
   }
   ```

3. **Prioritize by error code**
   - **CS0103/CS0246**: Missing type/namespace - check usings, references
   - **CS0029/CS0266**: Type conversion - check assignments
   - **CS1061**: Missing member - check spelling, interface
   - **CS0121**: Ambiguous call - add explicit cast or rename
   - **CS0506**: Cannot override - check virtual/override

   Fix in order: first error often causes cascading errors

4. **Create fix plan**
   ```
   ## Errors Found: X

   ### Error 1: CS0246 at File.cs:42
   The type or namespace 'IService' could not be found

   **Likely cause:** Missing using directive or package reference
   **Fix:** Add `using MyProject.Interfaces;`

   ### Error 2: ...
   ```

5. **Apply fixes**
   - Fix errors one at a time
   - After each fix, rebuild to check for cascading effects
   - Some fixes may resolve multiple errors

6. **Handle warnings** (optional)
   - After errors are fixed, present warnings
   - ASK if user wants warnings addressed

7. **Verify clean build**
   - Call `build_and_extract_errors`
   - Confirm zero errors
   - Report final status

## Common Error Patterns

| Code | Issue | Typical Fix |
|------|-------|-------------|
| CS0246 | Type not found | Add using, add package reference |
| CS0103 | Name not in scope | Check spelling, add using |
| CS1503 | Argument type mismatch | Cast, convert, or change parameter |
| CS0029 | Cannot convert type | Explicit cast or mapping |
| CS0535 | Interface not implemented | Implement missing members |
| CS0534 | Abstract member not implemented | Implement or make class abstract |

## Error Schema for Extraction

```json
{
  "type": "array",
  "items": {
    "type": "object",
    "properties": {
      "code": "string (e.g., CS0246)",
      "severity": "error|warning",
      "message": "string",
      "file": "string (path)",
      "line": "number",
      "column": "number"
    }
  }
}
```

## Rules

- MUST fix errors in order (first error first)
- MUST rebuild after each fix to check progress
- MUST NOT guess at fixes - investigate the cause
- If error is unclear, read the relevant source file
- If stuck on same error after 3 attempts, ASK for help
