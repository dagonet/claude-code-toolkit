# /traceability - Requirements Traceability

Link requirements to code to tests for full traceability.

## Arguments

- `$ARGUMENTS` - Requirement ID, feature name, or "full" for complete matrix

## Workflow

1. **Identify requirements source**
   - Check for requirements in:
     - GitHub issues with labels (requirement, feature, user-story)
     - Markdown files in /docs or /requirements
     - Comments with requirement IDs in code

2. **Build requirements list**
   - Call `list_issues` with appropriate filters
   - Read requirement documents if they exist
   - Extract requirement IDs and descriptions

3. **Find implementation**
   For each requirement, search for:
   - Code comments: `// REQ-001`, `// Implements #42`
   - Commit messages referencing issue numbers
   - Class/method names matching requirement

   Using Grep:
   ```
   - /REQ-\d+/
   - /#\d+/
   - /Implements|Closes|Fixes/
   ```

4. **Find tests**
   For each requirement, search for:
   - Test names containing requirement ID
   - Test attributes: `[Trait("Requirement", "REQ-001")]`
   - Test comments referencing requirements

5. **Build traceability matrix**
   ```markdown
   ## Traceability Matrix

   ### Summary
   | Status | Count | % |
   |--------|-------|---|
   | Fully Traced | 15 | 60% |
   | Partially Traced | 7 | 28% |
   | Untraceable | 3 | 12% |

   ### Full Matrix

   | Req ID | Description | Implementation | Tests | Status |
   |--------|-------------|----------------|-------|--------|
   | REQ-001 | User login | AuthService.cs:45 | AuthTests.cs:Login* | ✅ Full |
   | REQ-002 | Password reset | AuthService.cs:89 | (none) | ⚠️ Partial |
   | REQ-003 | User roles | (not found) | (none) | ❌ Missing |
   | #42 | Add caching | CacheService.cs | CacheTests.cs | ✅ Full |
   ```

6. **Identify gaps**

   ### Missing Implementation
   ```
   Requirements with no linked code:
   - REQ-003: User roles
   - REQ-007: Audit logging
   ```

   ### Missing Tests
   ```
   Requirements with code but no tests:
   - REQ-002: Password reset (AuthService.cs:89)
   - REQ-005: Rate limiting (RateLimiter.cs)
   ```

   ### Orphan Code
   ```
   Code not linked to any requirement:
   - LegacyProcessor.cs (entire file)
   - TempHelper.cs (entire file)
   ```

7. **Generate report**
   ```markdown
   ## Traceability Report

   ### Coverage Summary
   - Requirements: 25
   - With Implementation: 22 (88%)
   - With Tests: 18 (72%)
   - Fully Traced: 15 (60%)

   ### By Category

   #### Authentication (5 requirements)
   | Req | Impl | Test | Status |
   |-----|------|------|--------|
   | REQ-001 | ✅ | ✅ | Full |
   | REQ-002 | ✅ | ❌ | Partial |
   | REQ-003 | ❌ | ❌ | Missing |

   #### Payments (8 requirements)
   ...

   ### Gaps Analysis

   #### Critical Gaps (No Implementation)
   | Requirement | Priority | Notes |
   |-------------|----------|-------|
   | REQ-003 | High | Planned for Sprint 5 |

   #### Testing Gaps
   | Requirement | Implementation | Missing Tests |
   |-------------|----------------|---------------|
   | REQ-002 | AuthService.cs | Reset flow tests |

   #### Orphan Code (No Requirement)
   | File | Lines | Recommendation |
   |------|-------|----------------|
   | LegacyProcessor.cs | 450 | Document or deprecate |

   ### Recommendations
   1. Add tests for REQ-002 (Password reset)
   2. Implement REQ-003 (User roles)
   3. Add requirement tracking to LegacyProcessor
   4. Consider removing TempHelper.cs

   ### Traceability Improvement
   To improve traceability:
   1. Add `[Trait("Requirement", "REQ-XXX")]` to tests
   2. Use `// Implements REQ-XXX` in implementation
   3. Reference issue numbers in commit messages
   ```

## Traceability Patterns

### Code Comments
```csharp
/// <summary>
/// Implements REQ-001: User login functionality
/// See: https://github.com/org/repo/issues/42
/// </summary>
public async Task<LoginResult> Login(...)
```

### Test Attributes
```csharp
[Fact]
[Trait("Requirement", "REQ-001")]
[Trait("Category", "Authentication")]
public void Login_ValidCredentials_ReturnsToken()
```

### Commit Messages
```
feat: implement user login (#42)

Implements REQ-001
- Add AuthService.Login method
- Add JWT token generation
- Add password hashing
```

## Rules

- MUST link requirements → code → tests
- MUST identify gaps in each direction
- MUST report orphan code (no requirement)
- MUST report untested requirements
- Provide actionable recommendations
- Support multiple requirement sources (issues, docs, comments)
