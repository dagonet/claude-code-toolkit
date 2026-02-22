---
name: impact-analysis
description: Analyzes the impact of proposed changes on the codebase. Triggers when planning changes or asking about affected areas.
---

# Impact Analysis Skill

Analyze the impact of a proposed change on the codebase.

## When to Use

This skill auto-activates when:
- User asks "what will be affected if I change X?"
- User wants to understand change impact before implementing
- User mentions "impact", "affected", or "dependencies"
- User is planning a significant change or refactoring

## Workflow

1. **Understand the change**
   - Parse description for change details
   - If file path provided, read the file
   - Identify:
     - What is being changed?
     - Why is it being changed?
     - What is the expected outcome?

2. **Map dependencies**
   - Call `analyze_project_references(solution_or_dir)`
   - Call `map_dotnet_structure(root)`
   - Use Grep to find usages of changed component

3. **Identify affected areas**

   ### Direct Impact
   - Files that directly use the changed component
   - Projects that reference the changed project
   - Tests that test the changed code

   ### Indirect Impact
   - Code that depends on affected code
   - Downstream consumers
   - Configuration that references changed items

4. **Analyze by change type**

   #### API Change (Breaking)
   ```
   Method signature change: IService.GetUser(int id) → GetUser(Guid id)

   Direct Impact:
   - All callers of GetUser()
   - Integration tests
   - API clients

   Files Affected:
   - UserController.cs (line 45)
   - UserService.cs (line 23)
   - UserServiceTests.cs (lines 12, 34, 56)
   ```

   #### Schema Change (Database)
   ```
   Add column: Users.PreferredLanguage

   Direct Impact:
   - Entity class
   - Migrations
   - Queries referencing Users

   Indirect Impact:
   - DTOs that map from User
   - API responses
   - Reports
   ```

   #### Dependency Change
   ```
   Upgrade: Newtonsoft.Json 12.x → 13.x

   Direct Impact:
   - All JSON serialization code
   - Configuration

   Breaking Changes:
   - [List from changelog]
   ```

5. **Risk assessment**
   ```
   | Risk | Likelihood | Impact | Mitigation |
   |------|------------|--------|------------|
   | Breaking API clients | High | High | Version API |
   | Performance regression | Medium | Medium | Load test |
   | Data migration issues | Low | High | Backup first |
   ```

6. **Generate impact report**
   ```markdown
   ## Impact Analysis: [Change Description]

   ### Summary
   | Metric | Value |
   |--------|-------|
   | Files Affected | 12 |
   | Projects Affected | 4 |
   | Tests to Update | 8 |
   | Risk Level | Medium |

   ### Change Details
   **Component:** UserService
   **Change:** Add caching layer
   **Reason:** Performance improvement

   ### Dependency Graph
   ```
   UserService (CHANGED)
   ├── UserController (AFFECTED)
   │   └── UserControllerTests (UPDATE NEEDED)
   ├── OrderService (AFFECTED)
   │   └── OrderServiceTests (UPDATE NEEDED)
   └── ReportGenerator (AFFECTED)
   ```

   ### Files Requiring Changes

   #### Must Change
   | File | Reason |
   |------|--------|
   | UserService.cs | Add caching |
   | IUserService.cs | Update interface |

   #### May Need Changes
   | File | Reason |
   |------|--------|
   | UserController.cs | Cache invalidation |

   #### Tests to Update
   | Test File | Tests Affected |
   |-----------|----------------|
   | UserServiceTests.cs | 5 tests |
   | IntegrationTests.cs | 2 tests |

   ### Breaking Changes
   - [ ] API signature changed
   - [ ] Database schema changed
   - [ ] Configuration format changed

   ### Migration Steps
   1. Update interface
   2. Implement change
   3. Update tests
   4. Deploy with feature flag
   5. Enable feature
   6. Monitor

   ### Rollback Plan
   1. Disable feature flag
   2. No code rollback needed
   ```

## Rules

- MUST trace all dependencies (direct and indirect)
- MUST identify breaking changes
- MUST provide risk assessment
- MUST include rollback plan
- Consider both code and data impacts
