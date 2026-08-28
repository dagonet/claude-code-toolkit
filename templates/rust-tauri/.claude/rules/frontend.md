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

# Frontend (TypeScript/SolidJS)

- Wrap all Tauri IPC calls in typed functions in `src/lib/tauri-api.ts`
- Use `vi.mock("../lib/tauri-api")` pattern in tests to isolate components from Tauri IPC
- Tauri IPC only works in native window -- "Loading..." is expected in browser preview
- Use `npm test` for frontend tests (Vitest + @solidjs/testing-library)
