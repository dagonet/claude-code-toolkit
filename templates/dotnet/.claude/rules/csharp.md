---
paths:
  - "**/*.cs"
  - "**/*.csproj"
  - "**/*.props"
  - "**/*.targets"
  - ".editorconfig"
---

# Code Style (MANDATORY)

This repository uses a strict `.editorconfig` at the repository root.

All C# code MUST:
- follow `.editorconfig` exactly
- preserve formatting and naming rules
- avoid stylistic changes not required for correctness

Claude agents MUST NOT:
- reformat code that already complies
- introduce alternative styles
- override `.editorconfig` preferences

If generated code would violate `.editorconfig`,
the code MUST be rewritten until it complies.

## Enforcement Notes

- `.editorconfig` is committed and authoritative
- Formatting consistency is more important than brevity
- Explicit types are preferred over `var`
- Braces are always required
- Naming rules are strict and enforced

# .NET/C# Project Conventions

- Always verify `using` directives are present after merges or multi-file edits
- When adding new services, register them in the DI container AND verify mock registrations in test projects
- Check null-coalescing patterns when working with nullable types
- After branch merges, verify no `using` directives were dropped
- Run `dotnet format` to ensure `.editorconfig` compliance
