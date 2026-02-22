# /tech-debt - Technical Debt Assessment

Assess and quantify technical debt in the codebase.

## Arguments

- `$ARGUMENTS` - Path to assess, or "full" for complete solution

## Workflow

1. **Run quality analysis** (in parallel)
   - Call `analyze_method_complexity(root, threshold=10)`
   - Call `find_god_classes(root, method_threshold=20, field_threshold=15)`
   - Call `find_large_files(root, line_threshold=500)`
   - Call `nuget_list_outdated(project_or_sln)`
   - Call `analyze_namespace_conflicts(root)`

2. **Search for debt indicators** (using Grep)
   ```
   - TODO comments: /TODO|FIXME|HACK|XXX|TEMP/i
   - Suppressed warnings: /pragma warning disable|SuppressMessage/
   - Magic numbers: /[^a-zA-Z][0-9]{2,}[^0-9]/
   - Dead code: /unreachable code|never used/
   ```

3. **Categorize debt**

   ### Code Quality Debt
   - Complex methods (cyclomatic complexity > 10)
   - God classes (too many responsibilities)
   - Large files (> 500 lines)
   - Duplicate code
   - Magic numbers/strings

   ### Architecture Debt
   - Circular dependencies
   - Violated layer boundaries
   - Missing abstractions
   - Tight coupling

   ### Dependency Debt
   - Outdated packages (major versions behind)
   - Deprecated packages
   - Security vulnerabilities
   - Inconsistent versions

   ### Documentation Debt
   - Missing XML docs on public APIs
   - Outdated README
   - Missing architecture docs

   ### Test Debt
   - Low test coverage
   - Missing integration tests
   - Flaky tests
   - Tests without assertions

4. **Calculate debt score**
   ```
   Debt Points:
   - Critical complexity method: 10 pts each
   - God class: 15 pts each
   - Large file: 5 pts each
   - TODO/FIXME: 1 pt each
   - Outdated major version: 5 pts each
   - Security vulnerability: 20 pts each
   ```

5. **Estimate remediation effort**
   ```
   | Issue | Count | Effort/Item | Total |
   |-------|-------|-------------|-------|
   | Complex methods | 5 | 2h | 10h |
   | God classes | 2 | 8h | 16h |
   | Outdated packages | 10 | 1h | 10h |
   ```

6. **Generate report**
   ```markdown
   ## Technical Debt Assessment

   ### Debt Score: 245 points (High)

   | Threshold | Score Range |
   |-----------|-------------|
   | Low | 0-50 |
   | Medium | 51-150 |
   | High | 151-300 |
   | Critical | 300+ |

   ### Debt Breakdown

   | Category | Points | % of Total |
   |----------|--------|------------|
   | Code Quality | 120 | 49% |
   | Dependencies | 80 | 33% |
   | Architecture | 30 | 12% |
   | Documentation | 15 | 6% |

   ### Top Offenders

   | File | Issues | Points |
   |------|--------|--------|
   | BigService.cs | God class, 3 complex methods | 45 |
   | LegacyProcessor.cs | 800 lines, 5 TODOs | 25 |

   ### TODO/FIXME Summary
   - Total: 42 items
   - Oldest: 2 years (DataHelper.cs:120)
   - Categories: Bug fixes (15), Refactoring (20), Features (7)

   ### Outdated Dependencies
   | Package | Current | Latest | Behind |
   |---------|---------|--------|--------|
   | Newtonsoft.Json | 12.0.1 | 13.0.3 | Major |

   ### Remediation Roadmap

   #### Sprint 1 (Quick Wins)
   - Update patch-level dependencies
   - Fix security vulnerabilities
   - Estimated: 8 hours

   #### Sprint 2-3 (Code Quality)
   - Refactor top 3 god classes
   - Split large files
   - Estimated: 24 hours

   #### Sprint 4+ (Architecture)
   - Address circular dependencies
   - Extract missing abstractions
   - Estimated: 40 hours

   ### Trend (if historical data available)
   [Chart showing debt over time]
   ```

## Rules

- MUST quantify debt with points/hours
- MUST prioritize by impact and effort
- MUST provide actionable remediation plan
- Track debt over time if possible
- Focus on high-impact items first
