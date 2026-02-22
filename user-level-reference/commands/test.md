# /test - Run Tests and Fix Failures

Execute a test-fix-retest loop using MCP dotnet tools.

## Arguments

- `$ARGUMENTS` - Path to test project or solution (optional)

## Workflow

1. **Locate test project**
   - If path provided in `$ARGUMENTS`, use it
   - Otherwise, call `map_dotnet_structure(root)` to find test projects
   - Look for projects with "Test" or "Tests" in the name

2. **Run tests**
   - Call `run_tests_summary(project_or_sln, configuration="Debug")`
   - Parse the returned JSON for pass/fail/skip counts

3. **If all tests pass**
   - Report success with counts
   - Stop

4. **If failures exist**
   - List failing tests with their error messages
   - For each failure:
     - Read the test file to understand the test
     - Read the implementation being tested
     - Determine if test or implementation is wrong
     - Fix the appropriate code

5. **Retest**
   - After fixes, run tests again
   - Repeat until all tests pass or user stops

## Rules

- MUST use `run_tests_summary`, NOT raw `dotnet test` output
- MUST NOT paste full test output into chat
- MUST distinguish between test bugs and implementation bugs
- If a test looks incorrect, ASK before changing it
