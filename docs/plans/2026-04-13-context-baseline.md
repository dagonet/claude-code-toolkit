# Context Bloat Baseline — 2026-04-14

(token counts are approximate: tokens ≈ chars / 4)

## Top 10 sessions by file size

| rank | project | session | size_MB | msgs | peak_input_tokens | sum_bucket_chars |
|---|---|---|---|---|---|---|
| 1 | G--git-claude-code-toolkit | 2d3f42a8 | 10.9 | 3591 | 167308 | 3019338 |
| 2 | G--git-claude-code-toolkit | b0f59011 | 2.0 | 759 | 156428 | 546183 |
| 3 | G--git-claude-code-toolkit | fa2b29da | 1.8 | 532 | 126900 | 401537 |
| 4 | G--git-claude-code-toolkit | 8315b868 | 1.8 | 489 | 115537 | 320587 |
| 5 | G--git-claude-code-toolkit | efc00c83 | 1.6 | 406 | 125282 | 350446 |
| 6 | G--git-claude-code-toolkit | 28ae32de | 1.3 | 434 | 77416 | 231398 |
| 7 | G--git-claude-code-toolkit | 80fdbacd | 1.3 | 399 | 112121 | 242864 |
| 8 | G--git-claude-code-toolkit | 11b038ed | 1.3 | 533 | 121638 | 310867 |
| 9 | G--git-claude-code-toolkit | 5a6a020e | 1.1 | 460 | 121834 | 300710 |
| 10 | G--git-claude-code-toolkit | 86a74c90 | 1.1 | 344 | 107717 | 309094 |

## Aggregated buckets across top 10 (totals)

| bucket | chars | % of total |
|---|---|---|
| assistant | 3281764 | 54.4% |
| tool_result:Read | 1341625 | 22.2% |
| subagent_result | 528540 | 8.8% |
| claude_md | 132248 | 2.2% |
| tool_result:Bash | 125561 | 2.1% |
| tool_result:mcp__plugin_context-mode_context-mode__ctx_execute | 103331 | 1.7% |
| agent_team_md | 99289 | 1.6% |
| tool_result:ExitPlanMode | 77505 | 1.3% |
| tool_result:Grep | 65470 | 1.1% |
| tool_result:mcp__plugin_context-mode_context-mode__ctx_batch_execute | 57804 | 1.0% |
| tool_result:Edit | 56527 | 0.9% |
| skill_content | 52337 | 0.9% |
| tool_result:mcp__git-tools__git_status | 18027 | 0.3% |
| tool_result:Glob | 17960 | 0.3% |
| tool_result:Write | 11073 | 0.2% |
| tool_result:ToolSearch | 10453 | 0.2% |
| tool_result:mcp__git-tools__git_diff | 7171 | 0.1% |
| tool_result:mcp__git-tools__git_diff_summary | 6355 | 0.1% |
| tool_result:mcp__git-tools__git_push | 5397 | 0.1% |
| tool_result:mcp__git-tools__git_commit | 4481 | 0.1% |
| tool_result:mcp__git-tools__git_log | 4019 | 0.1% |
| tool_result:unknown | 3801 | 0.1% |
| tool_result:AskUserQuestion | 3676 | 0.1% |
| tool_result:TaskUpdate | 3496 | 0.1% |
| tool_result:TaskCreate | 3290 | 0.1% |
| tool_result:mcp__git-tools__git_add | 2887 | 0.0% |
| tool_result:mcp__git-tools__git_pull | 2697 | 0.0% |
| tool_result:mcp__git-tools__git_checkout | 1666 | 0.0% |
| tool_result:SendMessage | 1118 | 0.0% |
| tool_result:mcp__git-tools__git_stash | 1103 | 0.0% |
| tool_result:mcp__git-tools__git_branch_list | 980 | 0.0% |
| tool_result:mcp__github__create_pull_request | 816 | 0.0% |
| tool_result:TeamCreate | 302 | 0.0% |
| tool_result:TeamDelete | 255 | 0.0% |

## Per-session detail (top 3 by size)

### 1. G--git-claude-code-toolkit / 2d3f42a8 — 10.9 MB, peak 167308 tokens

| bucket | chars | % |
|---|---|---|
| assistant | 1934572 | 64.1% |
| tool_result:Read | 462802 | 15.3% |
| subagent_result | 158304 | 5.2% |
| tool_result:mcp__plugin_context-mode_context-mode__ctx_execute | 103331 | 3.4% |
| tool_result:Bash | 57817 | 1.9% |
| tool_result:mcp__plugin_context-mode_context-mode__ctx_batch_execute | 57804 | 1.9% |
| tool_result:ExitPlanMode | 56045 | 1.9% |
| skill_content | 46024 | 1.5% |
| tool_result:Edit | 27019 | 0.9% |
| tool_result:Grep | 26310 | 0.9% |
| tool_result:mcp__git-tools__git_status | 17475 | 0.6% |
| tool_result:ToolSearch | 8447 | 0.3% |
| agent_team_md | 8104 | 0.3% |
| tool_result:Write | 6745 | 0.2% |
| tool_result:mcp__git-tools__git_diff_summary | 6355 | 0.2% |
| tool_result:mcp__git-tools__git_push | 5135 | 0.2% |
| tool_result:mcp__git-tools__git_commit | 4159 | 0.1% |
| tool_result:AskUserQuestion | 3676 | 0.1% |
| claude_md | 3607 | 0.1% |
| tool_result:TaskUpdate | 3496 | 0.1% |
| tool_result:mcp__git-tools__git_log | 3394 | 0.1% |
| tool_result:TaskCreate | 3290 | 0.1% |
| tool_result:Glob | 3238 | 0.1% |
| tool_result:mcp__git-tools__git_add | 2709 | 0.1% |
| tool_result:mcp__git-tools__git_pull | 2697 | 0.1% |
| tool_result:mcp__git-tools__git_checkout | 1666 | 0.1% |
| tool_result:SendMessage | 1118 | 0.0% |
| tool_result:mcp__git-tools__git_stash | 1103 | 0.0% |
| tool_result:mcp__git-tools__git_branch_list | 980 | 0.0% |
| tool_result:mcp__github__create_pull_request | 816 | 0.0% |
| tool_result:unknown | 543 | 0.0% |
| tool_result:TeamCreate | 302 | 0.0% |
| tool_result:TeamDelete | 255 | 0.0% |

### 2. G--git-claude-code-toolkit / b0f59011 — 2.0 MB, peak 156428 tokens

| bucket | chars | % |
|---|---|---|
| assistant | 311218 | 57.0% |
| tool_result:Read | 116480 | 21.3% |
| subagent_result | 49396 | 9.0% |
| tool_result:Grep | 16747 | 3.1% |
| tool_result:ExitPlanMode | 15424 | 2.8% |
| tool_result:Bash | 11431 | 2.1% |
| tool_result:Glob | 8154 | 1.5% |
| claude_md | 8012 | 1.5% |
| tool_result:Edit | 7915 | 1.4% |
| tool_result:unknown | 543 | 0.1% |
| tool_result:Write | 353 | 0.1% |
| tool_result:ToolSearch | 284 | 0.1% |
| skill_content | 226 | 0.0% |

### 3. G--git-claude-code-toolkit / fa2b29da — 1.8 MB, peak 126900 tokens

| bucket | chars | % |
|---|---|---|
| assistant | 173632 | 43.2% |
| tool_result:Read | 106729 | 26.6% |
| agent_team_md | 43615 | 10.9% |
| tool_result:Bash | 34655 | 8.6% |
| subagent_result | 24370 | 6.1% |
| claude_md | 9836 | 2.4% |
| tool_result:Edit | 5025 | 1.3% |
| tool_result:Write | 1068 | 0.3% |
| tool_result:Glob | 655 | 0.2% |
| tool_result:Grep | 630 | 0.2% |
| tool_result:unknown | 543 | 0.1% |
| tool_result:ExitPlanMode | 524 | 0.1% |
| tool_result:ToolSearch | 142 | 0.0% |
| skill_content | 113 | 0.0% |

