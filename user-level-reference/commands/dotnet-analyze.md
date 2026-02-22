# /dotnet-analyze - Analyze .NET Code Quality

Perform comprehensive code quality analysis on a .NET project.

## Arguments

- `$ARGUMENTS` - Root directory or solution path (optional)

## Workflow

1. **Locate project**
   - If path provided in `$ARGUMENTS`, use it
   - Otherwise, use current directory

2. **Find namespace conflicts**
   - Call `analyze_namespace_conflicts(root, pattern="*.cs")`
   - Report any duplicate type definitions

3. **Find complex methods**
   - Call `analyze_method_complexity(root, threshold=10)`
   - List methods exceeding complexity threshold
   - Suggest refactoring for highly complex methods (>20)

4. **Find god classes**
   - Call `find_god_classes(root, method_threshold=20, field_threshold=15)`
   - Report classes that may need decomposition

5. **Find large files**
   - Call `find_large_files(root, line_threshold=500, pattern="*.cs")`
   - List files that may be too large

6. **Summarize findings**
   - Total issues by category
   - Priority recommendations:
     - CRITICAL: Namespace conflicts (will cause build errors)
     - HIGH: God classes (maintainability risk)
     - MEDIUM: Complex methods (bug risk)
     - LOW: Large files (readability concern)

## Rules

- Run all analysis tools in parallel for speed
- Present findings in priority order
- Suggest specific refactoring strategies for each issue
- Don't auto-fix - present findings for user review
