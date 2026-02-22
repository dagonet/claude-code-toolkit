# /new-feature - Scaffold a New Feature

Plan and scaffold a new feature with proper .NET architecture patterns.

## Arguments

- `$ARGUMENTS` - Feature name or description

## Workflow

1. **Understand the request**
   - Parse `$ARGUMENTS` for feature name and requirements
   - If unclear, ASK for clarification on:
     - Feature name (PascalCase)
     - Brief description
     - Which layer(s) it affects (API, Domain, Infrastructure, etc.)

2. **Analyze existing architecture**
   - Call `map_dotnet_structure(root)` to understand project layout
   - Call `analyze_project_references(solution_or_dir)` to understand layers
   - Identify naming conventions and patterns from existing code

3. **Plan the feature structure**
   - Determine which projects need new files:
     - Domain: Entities, Value Objects, Interfaces
     - Application: DTOs, Commands/Queries, Handlers, Validators
     - Infrastructure: Repositories, External Services
     - API: Controllers, Request/Response models
     - Tests: Unit tests, Integration tests

4. **Present the plan**
   ```
   ## Feature: [Name]

   ### Files to Create
   - [ ] src/Domain/Entities/[Name].cs
   - [ ] src/Application/[Name]/Commands/Create[Name]Command.cs
   - [ ] src/Application/[Name]/Queries/Get[Name]Query.cs
   - [ ] tests/UnitTests/[Name]Tests.cs

   ### Dependencies
   - [ ] Register in DI container
   - [ ] Add to DbContext (if applicable)
   ```

5. **Get approval**
   - ASK user to confirm before creating files

6. **Scaffold files**
   - Create each file following existing patterns
   - Use explicit types (no `var`)
   - Follow `.editorconfig` rules
   - Include XML documentation comments

7. **Register dependencies**
   - Update DI registration
   - Update DbContext if entity created
   - Update any configuration files

8. **Create initial tests**
   - Create test file with basic structure
   - Add placeholder tests for main scenarios

## Rules

- MUST analyze existing patterns before creating files
- MUST follow existing naming conventions
- MUST NOT create files without user approval
- MUST register all dependencies (DI, DbContext, etc.)
- Follow Clean Architecture / Onion Architecture if detected
