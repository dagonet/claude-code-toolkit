---
name: code-review
description: Performs comprehensive code review when reviewing PRs, branches, or code changes. Triggers on PR review requests, code quality checks, and change analysis.
---

# Code Review Skill

Perform a thorough code review with quality metrics and actionable feedback.

## When to Use

This skill auto-activates when:
- User asks to review a PR or pull request
- User asks to review code changes or a branch
- User wants code quality analysis on changes
- User mentions "review", "code review", or "check my changes"

## Workflow

1. **Get changes to review**
   - If PR number: fetch PR diff via GitHub MCP
   - If branch: `git_diff` against main/master
   - If file path: read the specific file
   - If "staged": `git_diff(staged=true)`
   - If empty: `git_diff` for unstaged changes

2. **Analyze code quality** (in parallel)
   - Call `analyze_method_complexity(root, threshold=10)` on changed files
   - Call `find_god_classes(root)` on changed files
   - Call `build_and_extract_errors` to check compilation

3. **Review checklist**

   ### Correctness
   - [ ] Logic is correct and handles edge cases
   - [ ] Error handling is appropriate
   - [ ] Null checks where needed
   - [ ] Async/await used correctly
   - [ ] Disposal of resources (IDisposable, using)

   ### Design
   - [ ] Single Responsibility Principle
   - [ ] Dependencies are injected, not created
   - [ ] Interfaces used for abstraction
   - [ ] No circular dependencies introduced
   - [ ] Follows existing patterns in codebase

   ### Security
   - [ ] No SQL injection vulnerabilities
   - [ ] No XSS vulnerabilities
   - [ ] Input validation present
   - [ ] Sensitive data not logged
   - [ ] Authentication/authorization checked

   ### Performance
   - [ ] No N+1 query patterns
   - [ ] Async for I/O operations
   - [ ] No unnecessary allocations in hot paths
   - [ ] Appropriate caching considered

   ### Maintainability
   - [ ] Code is readable and self-documenting
   - [ ] Complex logic has comments
   - [ ] Method/class size is reasonable
   - [ ] Naming is clear and consistent

   ### Testing
   - [ ] Tests added for new functionality
   - [ ] Edge cases covered
   - [ ] Tests are meaningful (not just coverage)

4. **Generate review report**
   ```markdown
   ## Code Review: [Context]

   ### Summary
   | Category | Status |
   |----------|--------|
   | Correctness | ✅ Pass |
   | Design | ⚠️ Minor issues |
   | Security | ✅ Pass |
   | Performance | ❌ Issues found |
   | Maintainability | ✅ Pass |
   | Testing | ⚠️ Missing tests |

   ### Issues Found

   #### 🔴 Critical
   - **File.cs:42** - SQL injection vulnerability
     ```csharp
     // Problem
     var sql = $"SELECT * FROM Users WHERE Name = '{name}'";
     // Suggestion
     var sql = "SELECT * FROM Users WHERE Name = @name";
     ```

   #### 🟡 Warnings
   - **Service.cs:100** - Method complexity: 15 (threshold: 10)
     Consider extracting into smaller methods

   #### 💡 Suggestions
   - **Controller.cs:25** - Consider using [FromServices] instead
   - **Model.cs:10** - Add XML documentation

   ### Metrics
   - Files changed: 5
   - Lines added: 120
   - Lines removed: 45
   - Complexity issues: 2

   ### Verdict
   [APPROVE / REQUEST CHANGES / COMMENT]
   ```

5. **Provide verdict**
   - **APPROVE**: No critical/high issues
   - **REQUEST CHANGES**: Critical or multiple high issues
   - **COMMENT**: Only suggestions, no blocking issues

## Rules

- MUST check all categories in checklist
- MUST provide specific line numbers and code examples
- MUST distinguish severity levels (Critical, Warning, Suggestion)
- MUST provide fix suggestions, not just identify problems
- Be constructive, not critical
