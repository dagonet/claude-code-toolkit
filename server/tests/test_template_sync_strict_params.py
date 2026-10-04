"""v4.3.1 S2: every MCP tool refuses an argument it does not declare; template_verify refuses an unknown mode."""

import asyncio
import json

import pytest
from mcp.server.fastmcp.exceptions import ToolError

from template_sync import mcp as ts


def test_every_tool_rejects_an_unknown_parameter():
    tools = ts.mcp._tool_manager.list_tools()
    assert sorted(t.name for t in tools) == ts._registered_tool_names()
    assert len(tools) >= 10
    for tool in tools:
        with pytest.raises(ToolError) as e:
            asyncio.run(ts.mcp.call_tool(tool.name, {"zz_not_a_param": 1}))
        msg = str(e.value)
        assert tool.name in msg and "zz_not_a_param" in msg and "nothing was run" in msg
        for accepted in tool.parameters.get("properties", {}):
            assert accepted in msg


def test_template_verify_phase_typo_is_refused_not_run(tmp_path):
    with pytest.raises(ToolError) as e:
        asyncio.run(ts.mcp.call_tool("template_verify", {"project_path": str(tmp_path), "phase": "pre_commit"}))
    assert "phase" in str(e.value) and "mode" in str(e.value)


def test_declared_parameters_still_dispatch(tmp_path):
    out = asyncio.run(ts.mcp.call_tool("template_verify", {"project_path": str(tmp_path), "mode": "pre_commit"}))
    assert '\\"mode\\": \\"pre_commit\\"' in str(out) or '"mode": "pre_commit"' in str(out)


def test_template_verify_rejects_an_unknown_mode_value(tmp_path):
    res = json.loads(asyncio.run(ts.template_verify(str(tmp_path), "", "precommit")))
    assert "precommit" in res["error"] and "pre_commit" in res["error"] and "post_commit" in res["error"]
    assert res["accepted_modes"] == ["pre_commit", "post_commit"]


def test_cli_verify_rejects_an_unknown_mode_value(tmp_path, capsys):
    assert ts._cli_verify([str(tmp_path), "--mode", "precommit"]) == 2
    assert "precommit" in capsys.readouterr().out
