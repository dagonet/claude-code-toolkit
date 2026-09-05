---
paths:
  - "**/*.xaml"
  - "**/*.xaml.cs"
---

# XAML / MAUI UI Conventions

- When adding UI behaviors (e.g., CommunityToolkit.Maui), verify the required NuGet package and namespace imports are in place
- When modifying XAML, verify ContentPage namespace declarations include all referenced assemblies

# Agent Routing and Build/Test Notes (moved from CLAUDE.md)

**Agent fallback:** If `dotnet-coder`'s MCP tools (dotnet-tools) are unavailable, it falls back to Bash `dotnet` equivalents. Do NOT substitute `coder` for `dotnet-coder` — it carries .NET-specific knowledge beyond MCP tool usage.

**Build & Test:** Use `dotnet build` + `dotnet test`; for slow suites, target first (`dotnet test --filter "FullyQualifiedName~ClassName"`) then run the full suite. For UI changes, publish the MAUI app and run smoke tests before claiming complete.

**Debugging:** trace read and write paths through Repository → Service → ViewModel → View — a common miss is fixing one direction but not the other.
