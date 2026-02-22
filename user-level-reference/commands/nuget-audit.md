# /nuget-audit - Audit NuGet Dependencies

Check NuGet packages for security vulnerabilities and updates.

## Arguments

- `$ARGUMENTS` - Path to .csproj or .sln file (optional)

## Workflow

1. **Locate project**
   - If path provided in `$ARGUMENTS`, use it
   - Otherwise, call `map_dotnet_structure(root)` to find projects

2. **Check for vulnerabilities**
   - Call `nuget_check_vulnerabilities(project_or_sln, include_transitive=true)`
   - Parse results for any security issues
   - Categorize by severity (Critical, High, Medium, Low)

3. **Check for outdated packages**
   - Call `nuget_list_outdated(project_or_sln, include_transitive=false)`
   - List packages with newer versions available
   - Note major vs minor vs patch updates

4. **Analyze dependency tree** (if issues found)
   - Call `nuget_dependency_tree(project_or_sln, include_transitive=true)`
   - Identify which direct dependencies pull in vulnerable transitives

5. **Generate report**
   ```
   ## Security Vulnerabilities
   [List by severity]

   ## Outdated Packages
   [List with current -> latest versions]

   ## Recommendations
   [Prioritized update suggestions]
   ```

6. **Suggest actions**
   - For vulnerabilities: Recommend immediate update or mitigation
   - For outdated: Suggest update strategy (patch first, then minor, then major)

## Rules

- ALWAYS check vulnerabilities first (security over features)
- Include transitive dependencies in vulnerability scan
- Warn about major version updates (may have breaking changes)
- Don't auto-update - present findings for user decision
