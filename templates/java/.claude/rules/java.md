---
paths:
  - "**/*.java"
  - "pom.xml"
  - "**/build.gradle*"
  - "src/main/resources/application.*"
---

# Code Style (MANDATORY)

This repository uses a project formatter (Spotless, Checkstyle, or google-java-format) as the authoritative style enforcer. The `.editorconfig` at the repository root provides supplementary whitespace and indent rules.

All Java code MUST:
- pass the project's configured formatter check without changes
- use `camelCase` for fields and methods
- use `UpperCamelCase` for classes and interfaces
- use `UPPER_SNAKE_CASE` for constants (`static final`)
- always use braces for `if`/`else`/`for`/`while` blocks
- use explicit imports (no wildcard `*` imports)

Claude agents MUST NOT:
- reformat code that already complies
- introduce alternative styles
- override `.editorconfig` or formatter preferences

If generated code would violate the project formatter,
the code MUST be rewritten until it complies.

## Enforcement Notes

- `.editorconfig` is committed and authoritative for whitespace
- The project formatter (Spotless/Checkstyle) is authoritative for Java style
- Formatting consistency is more important than brevity
- Run `{{FORMAT_COMMAND}}` before every commit

# Java/Spring Project Conventions

- Always verify `import` statements are present after merges or multi-file edits
- When adding new services, register them via `@Component`/`@Service`/`@Repository` annotations; verify `@ComponentScan` covers new packages
- Use **constructor injection** (not field injection) — Spring team recommended practice
- Use `Optional` for nullable return types, `@Nullable` for parameters
- Check `application.properties`/`application.yml` for new config entries
- After branch merges, verify no `import` directives were dropped
- Run `{{FORMAT_COMMAND}}` to ensure style compliance
