---
name: arch-analyze
description: Analyzes solution architecture, dependencies, and patterns. Triggers when asking about architecture or project structure analysis.
---

# Architecture Analysis Skill

Comprehensive analysis of .NET solution architecture, dependencies, and patterns.

## When to Use

This skill auto-activates when:
- User asks about architecture or solution structure
- User wants to understand project dependencies
- User mentions "architecture", "layers", or "dependency graph"
- User asks about Clean Architecture, Onion, or other patterns

## Workflow

1. **Locate solution**
   - If path provided, use it
   - Otherwise, call `map_dotnet_structure(root)` to find .sln files

2. **Gather structural data** (in parallel)
   - Call `analyze_project_references(solution_or_dir)`
   - Call `check_framework_compatibility(solution_or_dir)`
   - Call `nuget_dependency_tree(project_or_sln, include_transitive=true)`

3. **Identify architecture pattern**
   Detect which pattern is used:
   - **Clean Architecture**: Core/Domain → Application → Infrastructure → Presentation
   - **Onion Architecture**: Domain → Services → Infrastructure → UI
   - **N-Tier**: Data → Business → Presentation
   - **Vertical Slices**: Feature folders with all layers
   - **Modular Monolith**: Independent modules with shared kernel

4. **Analyze layers**
   ```
   ## Architecture Overview

   ### Pattern Detected: [Clean Architecture]

   ### Layer Analysis
   | Layer | Projects | Dependencies |
   |-------|----------|--------------|
   | Domain | Project.Domain | (none - innermost) |
   | Application | Project.Application | Domain |
   | Infrastructure | Project.Infrastructure | Application, Domain |
   | API | Project.API | Application |
   ```

5. **Check dependency rules**
   - Inner layers MUST NOT reference outer layers
   - Flag violations:
     ```
     VIOLATION: Domain references Infrastructure
     File: Domain.csproj → Infrastructure.csproj
     ```

6. **Analyze coupling**
   - Count dependencies per project
   - Identify highly coupled projects (> 5 dependencies)
   - Identify orphan projects (no dependents)

7. **Check for issues**
   - Circular dependencies
   - Framework mismatches
   - Shared dependencies that should be abstracted
   - Missing abstractions (direct infrastructure references)

8. **Generate report**
   ```markdown
   ## Architecture Analysis Report

   ### Summary
   - Pattern: Clean Architecture
   - Projects: 8
   - Dependency Violations: 2
   - Framework Alignment: OK

   ### Dependency Graph
   ```
   API
   └── Application
       └── Domain
   Infrastructure
   ├── Application
   └── Domain
   ```

   ### Layer Violations
   1. Domain → Infrastructure (line X in Domain.csproj)
      **Fix:** Extract interface to Domain layer

   ### Coupling Analysis
   | Project | Dependents | Dependencies | Coupling |
   |---------|------------|--------------|----------|
   | Domain | 4 | 0 | Low |
   | Utils | 6 | 2 | High |

   ### Framework Compatibility
   | Project | Framework |
   |---------|-----------|
   | All | net8.0 ✅ |

   ### Recommendations
   1. Extract interface for [Service] to Domain layer
   2. Move [Class] from Infrastructure to Application
   3. Consider splitting Utils into focused packages
   ```

## Dependency Rules by Pattern

### Clean Architecture
```
UI/API → Application → Domain
           ↓
      Infrastructure
```
- Domain: No dependencies
- Application: Only Domain
- Infrastructure: Application + Domain
- UI/API: Application only

### Onion Architecture
```
UI → Application → Domain Services → Domain Model
              ↓
         Infrastructure
```

## Rules

- MUST detect actual pattern, not assume
- MUST flag all dependency rule violations
- MUST identify circular dependencies
- Report should be actionable with specific fixes
