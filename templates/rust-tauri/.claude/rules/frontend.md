---
paths:
  - "src/**/*.ts"
  - "src/**/*.tsx"
  - "**/*.css"
  - ".prettierrc"
---

# Code Style (MANDATORY)

This repository uses `.prettierrc` (TypeScript) at the repository root.

All TypeScript/CSS code MUST:
- pass `npm run format -- --check` (Prettier) without changes
- pass `npm run lint` without errors

Claude agents MUST NOT:
- reformat code that already complies
- introduce alternative styles or override formatter preferences

If generated code would violate formatting rules,
the code MUST be rewritten until it complies.

## Enforcement Notes

- `.prettierrc` is committed and authoritative
- Run `npm run format` before committing
- Naming convention: `camelCase` for TypeScript

# Frontend (TypeScript)

Framework-agnostic — this rule loads for every `src/**/*.ts` touch, so it states
only what holds regardless of the UI framework the project picked.

- Keep Tauri IPC behind typed wrapper functions in one module, and import that
  module rather than calling `invoke` from components. Tests then mock one path.
- Tauri IPC only works in the native window — a loading placeholder is expected
  in browser preview, and is not a bug to chase.
- Run frontend tests with `npm test`; mock the IPC wrapper module, never the
  Tauri runtime.
