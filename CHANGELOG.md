# Changelog

## 2026-04-26 — Open Brain v0.3.0 sync

Synced template and reference docs to match Open Brain v0.3.0 (mcp-server@0.3.0, 14 tools): the existing `thoughts_*` and `system_status` tools are joined by a write-time wiki layer (`wiki_get`, `wiki_list`, `wiki_refresh`) and on-demand contradiction surfacing (`contradictions_list`, `contradictions_resolve`, `contradictions_audit`). Documents the per-repo opt-out env var `OPEN_BRAIN_TOOLS_DISABLED=wiki,contradictions`.

The session-bootstrap directive in `CLAUDE.md` keeps the unconditional `thoughts_search`/`thoughts_recent` mandate; the wiki-first rule is appended as an intentionally conditional follow-up for synthesis-style questions on a known topic, gated on the page being non-stale (`stale_since_n_thoughts > 5`, `open_contradictions_count > 0`, or `compiled_at` older than 7 days). The three-layer enforcement structure (`CLAUDE.md` bootstrap → MCP server instructions → `CLAUDE.local.md` hard requirement) is preserved — only extended.

Files touched: `templates/<6 variants>/CLAUDE.md`, `templates/<6 variants>/CLAUDE.local.md`, `user-level-reference/README.md`, `mcp-servers/HOWTO.md`, `docs/architecture.md`. `settings.json` and `settings-reference.md` already use the `mcp__open-brain__*` wildcard, so the new tools are permitted automatically.

Upstream: https://github.com/dagonet/open-brain/pull/7

Inspired-by: karpathy/442a6bf555914893e9891c11519de94f (gist) via Nate B Jones (youtu.be/dxq7WtWxi44)
