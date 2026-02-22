# /dependency-audit - Audit Project Dependencies

Find circular dependencies, orphan projects, and framework mismatches.

## Arguments

- `$ARGUMENTS` - Path to solution (optional)

## Workflow

1. **Locate solution**
   - If path in `$ARGUMENTS`, use it
   - Otherwise, call `map_dotnet_structure(root)` to find .sln

2. **Analyze dependencies** (in parallel)
   - Call `analyze_project_references(solution_or_dir)`
   - Call `check_framework_compatibility(solution_or_dir)`
   - Call `nuget_dependency_tree(project_or_sln, include_transitive=true)`

3. **Detect circular dependencies**
   - Build dependency graph
   - Find cycles using depth-first search
   - Report all cycles found:
     ```
     CIRCULAR DEPENDENCY DETECTED:
     ProjectA → ProjectB → ProjectC → ProjectA
     ```

4. **Find orphan projects**
   - Projects with no dependents (nothing references them)
   - Exclude entry points (API, Console apps, Tests)
   ```
   ORPHAN PROJECTS (no dependents):
   - Project.Legacy (not referenced by any project)
   - Project.Unused (not referenced by any project)
   ```

5. **Check framework alignment**
   - All projects should target compatible frameworks
   - Flag mismatches:
     ```
     FRAMEWORK MISMATCH:
     - Project.Core: net8.0
     - Project.Legacy: net6.0  ← May cause issues
     ```

6. **Analyze NuGet dependencies**
   - Find duplicate packages with different versions
   - Find packages referenced at multiple levels
   ```
   VERSION CONFLICTS:
   - Newtonsoft.Json: 13.0.1 (ProjectA), 12.0.3 (ProjectB)

   DUPLICATE TRANSITIVE:
   - Microsoft.Extensions.Logging pulled by 5 packages
   ```

7. **Check for problematic patterns**
   - Test projects referencing production internals
   - Shared projects with too many dependents
   - Deep dependency chains (> 5 levels)

8. **Generate report**
   ```
   ## Dependency Audit Report

   ### Summary
   | Issue Type | Count | Severity |
   |------------|-------|----------|
   | Circular Dependencies | 1 | CRITICAL |
   | Orphan Projects | 2 | MEDIUM |
   | Framework Mismatches | 1 | HIGH |
   | Version Conflicts | 3 | MEDIUM |

   ### Critical Issues

   #### Circular Dependency #1
   Path: A → B → C → A
   **Fix:** Extract shared code to new project D

   ### High Priority Issues

   #### Framework Mismatch
   Project.Legacy targets net6.0
   **Fix:** Upgrade to net8.0 or create compatibility shim

   ### Medium Priority Issues

   #### Orphan: Project.Unused
   No projects reference this
   **Fix:** Remove from solution or document why it exists
   ```

## Circular Dependency Resolution Strategies

1. **Extract Interface**: Move shared interface to a third project
2. **Merge Projects**: If tightly coupled, consider merging
3. **Invert Dependency**: Use dependency injection to flip direction
4. **Event-Based**: Use events/mediator to decouple

## Rules

- CRITICAL: Circular dependencies must be reported prominently
- MUST distinguish between project and package dependencies
- MUST provide actionable fix suggestions
- Orphan detection should exclude entry-point projects
