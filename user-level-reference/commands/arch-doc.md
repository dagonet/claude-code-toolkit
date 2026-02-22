# /arch-doc - Generate Architecture Documentation

Generate architecture documentation from code analysis.

## Arguments

- `$ARGUMENTS` - Output format (markdown, mermaid) or specific focus area

## Workflow

1. **Analyze solution structure**
   - Call `map_dotnet_structure(root)`
   - Call `analyze_project_references(solution_or_dir)`
   - Call `check_framework_compatibility(solution_or_dir)`

2. **Identify key components**
   - Read main entry points (Program.cs, Startup.cs)
   - Identify DI registrations
   - Find configuration files (appsettings.json)
   - Locate key interfaces and implementations

3. **Map project purposes**
   For each project, determine:
   - Layer (Domain, Application, Infrastructure, Presentation)
   - Responsibility (API, Services, Data Access, etc.)
   - Key classes and interfaces

4. **Generate dependency diagram**
   ```mermaid
   graph TB
       subgraph Presentation
           API[Project.API]
       end
       subgraph Application
           App[Project.Application]
       end
       subgraph Domain
           Dom[Project.Domain]
       end
       subgraph Infrastructure
           Infra[Project.Infrastructure]
           Data[Project.Data]
       end

       API --> App
       App --> Dom
       Infra --> App
       Infra --> Dom
       Data --> Dom
   ```

5. **Document layers**
   ```markdown
   ## Domain Layer

   ### Entities
   - `User` - Core user entity
   - `Order` - Order aggregate root

   ### Interfaces
   - `IUserRepository` - User persistence contract
   - `IOrderService` - Order business operations

   ## Application Layer

   ### Commands
   - `CreateOrderCommand` - Creates a new order

   ### Queries
   - `GetUserQuery` - Retrieves user by ID
   ```

6. **Document external dependencies**
   - NuGet packages and their purposes
   - External services and APIs
   - Database providers

7. **Document configuration**
   - Environment variables
   - App settings structure
   - Feature flags

8. **Generate output**
   Based on `$ARGUMENTS`:
   - **markdown**: Full documentation in Markdown
   - **mermaid**: Focus on diagrams
   - **c4**: C4 model diagrams (Context, Container, Component)

## Output Template

```markdown
# [Solution Name] Architecture

## Overview
[Brief description of the system]

## Technology Stack
- Framework: .NET 8
- Database: SQL Server
- Messaging: RabbitMQ

## Project Structure
[Dependency diagram]

## Layers

### Domain
[Description and key components]

### Application
[Description and key components]

### Infrastructure
[Description and key components]

### Presentation
[Description and key components]

## Data Flow
[Sequence diagrams for key operations]

## Deployment
[Deployment architecture if detectable]
```

## Rules

- MUST generate from actual code analysis, not assumptions
- MUST include dependency diagrams
- MUST document all projects and their purposes
- Keep documentation concise and actionable
- Use Mermaid for diagrams (widely supported)
