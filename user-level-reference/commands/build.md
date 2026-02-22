# /build - Build Project and Fix Errors

Execute a build-fix-rebuild loop using MCP dotnet tools.

## Arguments

- `$ARGUMENTS` - Path to .csproj or .sln file (optional, will search if not provided)

## Workflow

1. **Locate project**
   - If path provided in `$ARGUMENTS`, use it
   - Otherwise, call `map_dotnet_structure(root)` to find .sln or .csproj files
   - Prefer .sln if multiple projects exist

2. **Build**
   - Call `build_and_extract_errors(project_or_sln, configuration="Debug")`
   - Parse the returned JSON for errors and warnings

3. **If errors exist**
   - List errors in priority order (first error first)
   - Fix each error by editing the relevant file
   - After fixing, rebuild to verify

4. **Repeat until clean**
   - Continue the build-fix cycle until no errors remain
   - Report final status: success or remaining issues

5. **Report warnings** (optional)
   - If build succeeds but warnings exist, list them
   - Ask user if they want warnings addressed

## Rules

- MUST use `build_and_extract_errors`, NOT raw `dotnet build` output
- MUST fix errors in order (first error often causes cascading errors)
- MUST NOT paste raw MSBuild output into chat
- If build fails repeatedly on same error, investigate root cause
