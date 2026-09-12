---
paths:
  - "**/*.rs"
  - "rustfmt.toml"
  - "Cargo.toml"
---

# Code Style (MANDATORY)

This repository uses `rustfmt.toml` at the repository root.

All Rust code MUST:
- pass `cargo fmt --check` without changes
- pass `cargo clippy -- -D warnings` without warnings
- follow `rustfmt.toml` settings exactly

Claude agents MUST NOT:
- reformat code that already complies
- introduce alternative styles or override formatter preferences
- suppress clippy warnings without justification

If generated code would violate formatting rules,
the code MUST be rewritten until it complies.

## Enforcement Notes

- `rustfmt.toml` is committed and authoritative
- Run `cargo fmt` before committing
- Treat clippy warnings as errors (`-D warnings`)
- Naming convention: `snake_case` for Rust

# Backend (Rust)

- Use `cargo test` to run Rust tests, `cargo clippy` for lints, `cargo fmt` for formatting
- Use `impl` blocks in service files (e.g., `*_service.rs`) for business logic
- IPC commands go in `commands.rs` as thin wrappers calling service methods
- Register all commands in `lib.rs`
- Use structured logging via the `log` crate
- Prefer `rusqlite` with `params![]` macro for SQL queries (not string interpolation)

# Build, Routing, and Directory Notes (moved from CLAUDE.md)

**Commands (build, test, format, lint, gate):** see `PROJECT_CONTEXT.md` at the project root — the single source; do not copy them here.

**Directory overview:** `src/` (frontend TypeScript), `src-tauri/src/` (Rust backend), `e2e/` (E2E tests), `docs/plans/` (design docs + sprint plans).

**Agent fallback:** If `rust-coder`'s MCP tools (rust-tools) are unavailable, it falls back to Bash `cargo` equivalents. Do NOT substitute `coder` for `rust-coder` — it carries Rust/Tauri-specific knowledge beyond MCP tool usage.

**Build & Test:** run `cargo build` + `cargo test` (backend) + `npm test` (frontend), and `cargo clippy -- -D warnings` before committing.

**Debugging:** trace read and write paths through the full IPC flow (frontend → tauri command → service → repository) — a common miss is fixing one direction but not the other.
