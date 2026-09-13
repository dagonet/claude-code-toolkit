"""template_get_diff accepts diff_type="unified" as an alias of "full" (review §2.11)."""

import asyncio
import json

from template_sync import mcp as ts


def test_get_diff_accepts_unified_as_alias_of_full(tmp_path):
    repo = tmp_path / "toolkit"
    (repo / "templates" / "general").mkdir(parents=True)
    (repo / "templates" / "general" / "CLAUDE.md").write_text("a\nb\n", encoding="utf-8", newline="")
    proj = tmp_path / "proj"
    (proj / ".claude").mkdir(parents=True)
    (proj / "CLAUDE.md").write_text("a\nc\n", encoding="utf-8", newline="")
    (proj / ".claude" / "template-manifest.json").write_text(json.dumps({
        "version": 2, "templateRepo": str(repo), "variant": "general", "placeholders": {},
        "lastSynced": "", "files": {"CLAUDE.md": {"templateHash": ts._sha256("a\nb\n")}},
    }), encoding="utf-8")
    full = json.loads(asyncio.run(ts.template_get_diff(str(proj), "CLAUDE.md", "full")))
    uni = json.loads(asyncio.run(ts.template_get_diff(str(proj), "CLAUDE.md", "unified")))
    assert uni["diff_type"] == "unified"
    assert uni["unified_diff"] == full["unified_diff"]
    assert "-b" in uni["unified_diff"] and "+c" in uni["unified_diff"]
