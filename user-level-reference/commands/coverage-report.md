# /coverage-report - Test Coverage Analysis

Analyze test coverage and identify gaps.

## Arguments

- `$ARGUMENTS` - Path to project/solution, or minimum threshold (e.g., "80%")

## Workflow

1. **Run tests with coverage**
   - Call `run_coverage(project_or_sln, configuration="Debug")`
   - This generates Cobertura XML report

2. **Parse coverage report**
   - Call `parse_coverage_report(report_path)`
   - Extract line, branch, and method coverage

3. **Analyze coverage by project**
   ```
   | Project | Line % | Branch % | Method % |
   |---------|--------|----------|----------|
   | Domain | 85% | 72% | 90% |
   | Application | 78% | 65% | 82% |
   | Infrastructure | 45% | 30% | 55% |
   ```

4. **Identify coverage gaps**
   - Files with < 50% coverage
   - Critical paths without tests
   - Complex methods without coverage

5. **Analyze by component type**
   ```
   | Component Type | Avg Coverage |
   |----------------|--------------|
   | Controllers | 75% |
   | Services | 82% |
   | Repositories | 60% |
   | Validators | 90% |
   | Helpers | 45% |
   ```

6. **Find untested critical code**
   - Public APIs without tests
   - Exception handlers
   - Validation logic
   - Security-related code

7. **Generate report**
   ```markdown
   ## Coverage Report

   ### Summary
   | Metric | Value | Target | Status |
   |--------|-------|--------|--------|
   | Line Coverage | 72% | 80% | ❌ Below |
   | Branch Coverage | 58% | 70% | ❌ Below |
   | Method Coverage | 78% | 80% | ⚠️ Close |

   ### Coverage Trend
   | Date | Line % | Change |
   |------|--------|--------|
   | Current | 72% | - |
   | Previous | 70% | +2% |

   ### Coverage by Project
   | Project | Lines | Branches | Status |
   |---------|-------|----------|--------|
   | Domain | 85% | 72% | ✅ |
   | Application | 78% | 65% | ⚠️ |
   | Infrastructure | 45% | 30% | ❌ |

   ### Lowest Coverage Files
   | File | Coverage | Lines Uncovered |
   |------|----------|-----------------|
   | LegacyService.cs | 23% | 145/188 |
   | DataProcessor.cs | 35% | 89/137 |
   | CacheHelper.cs | 40% | 24/40 |

   ### Uncovered Critical Code
   1. **PaymentService.ProcessRefund** - 0% coverage
      - Risk: Financial operations untested
      - Priority: Critical

   2. **AuthController.ResetPassword** - 15% coverage
      - Risk: Security flow poorly tested
      - Priority: High

   ### Recommended Tests to Add

   #### High Priority (Critical paths)
   1. PaymentService.ProcessRefund
      - Happy path test
      - Insufficient funds test
      - Partial refund test

   2. AuthController.ResetPassword
      - Valid token test
      - Expired token test
      - Invalid user test

   #### Medium Priority (Coverage gaps)
   1. DataProcessor - Add integration tests
   2. CacheHelper - Add unit tests for edge cases

   ### Coverage Exclusions
   Files excluded from coverage:
   - *.Designer.cs
   - Migrations/*
   - Program.cs

   ### Action Items
   1. Add tests for PaymentService (estimated: 4h)
   2. Add tests for AuthController (estimated: 2h)
   3. Improve Infrastructure coverage (estimated: 8h)
   ```

## Coverage Thresholds

| Level | Line | Branch | Method |
|-------|------|--------|--------|
| Excellent | 90%+ | 80%+ | 95%+ |
| Good | 80%+ | 70%+ | 85%+ |
| Acceptable | 70%+ | 60%+ | 75%+ |
| Poor | <70% | <60% | <75% |

## Coverage Best Practices

- **Focus on critical paths** over raw numbers
- **Branch coverage** often more valuable than line coverage
- **Don't test generated code** (DTOs, migrations)
- **Integration tests** count too, not just unit tests
- **Diminishing returns** above 90% - focus elsewhere

## Rules

- MUST show coverage by project/component
- MUST identify critical untested code
- MUST prioritize recommendations by risk
- Compare against target threshold
- Suggest specific tests to add, not just "add more tests"
