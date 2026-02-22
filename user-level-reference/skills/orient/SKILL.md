---
name: orient
description: Quickly understand and map a project's structure and architecture. Triggers when exploring new codebases or asking about project layout.
---

# Project Orientation Skill

Quickly understand the structure and architecture of the current project.

## When to Use

This skill auto-activates when:
- User opens a new project or repository
- User asks "what is this project?", "how is this structured?"
- User wants to understand the codebase architecture
- User asks about project layout, dependencies, or entry points

## Workflow

1. **Map structure**
   - For .NET projects: Call `map_dotnet_structure(root)`
   - For other projects: Call `map_project_structure(root, include="*")`

2. **Identify key files**
   - Solution/project files (.sln, .csproj, package.json, etc.)
   - Entry points (Program.cs, main.py, index.ts, etc.)
   - Configuration files (.editorconfig, appsettings.json, etc.)
   - Test directories

3. **Analyze architecture**
   - For .NET: Call `analyze_project_references(solution_or_dir)` to understand project dependencies
   - Identify layers (API, Domain, Infrastructure, Tests)
   - Note any circular dependencies or orphan projects

4. **Check for issues**
   - Call `check_framework_compatibility(solution_or_dir)` for .NET projects
   - Call `analyze_namespace_conflicts(root)` if namespace issues are suspected

5. **Summarize**
   - Project type and framework
   - Directory structure overview
   - Key entry points and configuration
   - Notable patterns or concerns

## Output Format

```markdown
## Project: [Name]

### Type
[.NET 8 Web API / Node.js / etc.]

### Structure
```
Solution/
├── src/
│   ├── Domain/          # Core business logic
│   ├── Application/     # Use cases
│   ├── Infrastructure/  # External concerns
│   └── API/             # Entry point
└── tests/
    └── UnitTests/
```

### Key Files
- **Entry point**: src/API/Program.cs
- **Configuration**: appsettings.json
- **Solution**: Solution.sln

### Architecture
[Clean Architecture / N-Tier / etc.]

### Dependencies
[Project dependency graph]

### Notable Patterns
- [Pattern 1]
- [Pattern 2]

### Potential Issues
- [Issue if any]
```

## Rules

- MUST use MCP tools for exploration, NOT manual file browsing
- MUST NOT open random files without structural justification
- Keep summary concise - user can ask for details
