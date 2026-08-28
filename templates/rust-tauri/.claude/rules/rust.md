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
