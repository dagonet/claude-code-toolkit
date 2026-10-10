# Process baseline before v4.5 (scripts/measure-process.py)

Window: every transcript on this machine whose first timestamp is on or before 2026-10-05; Claude Code deletes older ones, so the window starts wherever each project's oldest surviving transcript does. Measured 2026-10-05 at 929bd96. The toolkit releases in the window are v4.3.0 and whatever v4.3.1/v4.4.0 each consumer had synced; the file keeps the spec's name.

## Process vs progress: G--git-InvestmentAdvisor, start to 2026-10-05

### subagents (0 transcripts)

| Bucket | Events | Load (tokens) | Output tokens | Wall (s) |
|---|---|---|---|---|

Process share, process / (process + progress): load None, output None, wall None. Model time (span minus tool time): 0 s.
Unclassified, top tools: none

### main (0 transcripts)

| Bucket | Events | Load (tokens) | Output tokens | Wall (s) |
|---|---|---|---|---|

Process share, process / (process + progress): load None, output None, wall None. Model time (span minus tool time): 0 s.
Unclassified, top tools: none

### spawn

| Agent type | Runs | Mean prompt B | Mean Skill B | Runs with a Skill | TDD opened, by tier | Skills opened |
|---|---|---|---|---|---|---|

### report

Coder final reports: n 0, mean 0 B, median 0 B, `## Gate Results` share 0.0; short form 0, legacy form 0.

### prod

Coder runs with at least one contract prod: 0 of 0.


## Process vs progress: G--git-KnowledgeGame, start to 2026-10-05

### subagents (0 transcripts)

| Bucket | Events | Load (tokens) | Output tokens | Wall (s) |
|---|---|---|---|---|

Process share, process / (process + progress): load None, output None, wall None. Model time (span minus tool time): 0 s.
Unclassified, top tools: none

### main (0 transcripts)

| Bucket | Events | Load (tokens) | Output tokens | Wall (s) |
|---|---|---|---|---|

Process share, process / (process + progress): load None, output None, wall None. Model time (span minus tool time): 0 s.
Unclassified, top tools: none

### spawn

| Agent type | Runs | Mean prompt B | Mean Skill B | Runs with a Skill | TDD opened, by tier | Skills opened |
|---|---|---|---|---|---|---|

### report

Coder final reports: n 0, mean 0 B, median 0 B, `## Gate Results` share 0.0; short form 0, legacy form 0.

### prod

Coder runs with at least one contract prod: 0 of 0.


## Process vs progress: G--git-Motorsport-Manager-AI-Agent, start to 2026-10-05

### subagents (1290 transcripts)

| Bucket | Events | Load (tokens) | Output tokens | Wall (s) |
|---|---|---|---|---|
| process:review | 7471 | 184920377 | 3761116 | 42957 |
| process:test | 268 | 5240117 | 45680 | 1752 |
| process:rules | 1379 | 204992799 | 75239 | 1314 |
| process:prod | 2522 | 30489521 | 936327 | 50084 |
| process:report | 1290 | 52584 | 699861 | 1050 |
| process:gate | 4522 | 118590602 | 939434 | 577213 |
| process:wait | 547 | 3167399 | 79628 | 1399 |
| progress:commit | 299 | 1449177 | 85342 | 7 |
| progress:edit | 10600 | 38635012 | 6134010 | 23759 |
| progress:deliver | 417 | 2704871 | 61138 | 6687 |
| neutral:orient | 59873 | 2497218682 | 20224866 | 1309326 |
| neutral:spawn | 640 | 40898992 | 0 | 0 |
| unclassified | 7203 | 74409944 | 3188392 | 112312 |

Process share, process / (process + progress): load 0.9275, output 0.51, wall 0.9569. Model time (span minus tool time): 1712202 s.
Unclassified, top tools: SendMessage 1029, TaskUpdate 833, mcp__git-tools__git_status 753, mcp__git-tools__git_log 600, mcp__plugin_context-mode_context-mode__ctx_execute 490, mcp__git-tools__git_add 407, mcp__git-tools__git_commit 405, TaskCreate 394, mcp__git-tools__git_diff_summary 212, mcp__plugin_context-mode_context-mode__ctx_batch_execute 198

### main (1 transcripts)

| Bucket | Events | Load (tokens) | Output tokens | Wall (s) |
|---|---|---|---|---|
| process:rules | 32 | 1509924395 | 18755 | 159 |
| process:gate | 154 | 175900025 | 98857 | 390817 |
| process:wait | 974 | 706458260 | 82253 | 1344 |
| progress:commit | 337 | 99379935 | 372917 | 5 |
| progress:edit | 2573 | 1120703569 | 2777605 | 4469 |
| progress:deliver | 150 | 51133262 | 85987 | 5031 |
| neutral:orient | 11188 | 14031767615 | 4590849 | 205005 |
| neutral:spawn | 2203 | 2449687309 | 2606366 | 6467 |
| unclassified | 13809 | 35866880437 | 4145487 | 809281 |

Process share, process / (process + progress): load 0.653, output 0.0582, wall 0.9763. Model time (span minus tool time): 5371221 s.
Unclassified, top tools: mcp__plugin_context-mode_context-mode__ctx_execute 2980, SendMessage 2384, mcp__git-tools__git_commit 1082, mcp__git-tools__git_add 981, mcp__open-brain__thoughts_capture 781, TaskUpdate 721, TaskCreate 579, mcp__git-tools__git_status 568, mcp__git-tools__git_branch_delete 474, mcp__git-tools__git_log 470

### spawn

| Agent type | Runs | Mean prompt B | Mean Skill B | Runs with a Skill | TDD opened, by tier | Skills opened |
|---|---|---|---|---|---|---|
| Explore | 44 | 4856 | 0 | 0 | unknown 0/44 | none |
| Plan | 1 | 9876 | 0 | 0 | T3 0/1 | none |
| ab-challenger | 1 | 6529 | 22466 | 1 | unknown 0/1 | context-mode:context-mode 1, superpowers:writing-plans 1 |
| api-coverage | 1 | 6985 | 0 | 0 | unknown 0/1 | none |
| architect | 112 | 6276 | 5225 | 73 | T2 0/9, T3 0/10, T4 0/7, unknown 0/86 | superpowers:writing-plans 69, superpowers:systematic-debugging 4 |
| autofit-check | 1 | 6472 | 0 | 0 | unknown 0/1 | none |
| batch-h-launcher | 1 | 5481 | 0 | 0 | unknown 0/1 | none |
| blocklist-audit | 1 | 6104 | 0 | 0 | unknown 0/1 | none |
| bonus-audit | 1 | 6389 | 0 | 0 | unknown 0/1 | none |
| bonus-career-gate | 1 | 6413 | 0 | 0 | unknown 0/1 | none |
| box-verify | 1 | 6381 | 0 | 0 | unknown 0/1 | none |
| boxrun | 1 | 6738 | 0 | 0 | unknown 0/1 | none |
| code-reviewer | 19 | 5828 | 0 | 0 | T2 0/1, T3 0/1, unknown 0/17 | none |
| commission-live | 1 | 6457 | 0 | 0 | unknown 0/1 | none |
| condition-coder | 1 | 7233 | 21574 | 1 | unknown 1/1 | superpowers:receiving-code-review 2, karpathy-guidelines 1, superpowers:test-driven-development 1, superpowers:verification-before-completion 1 |
| condition-fix-probe | 1 | 5568 | 0 | 0 | unknown 0/1 | none |
| crash-capture | 1 | 5668 | 0 | 0 | unknown 0/1 | none |
| deadlock-worth | 1 | 6033 | 0 | 0 | unknown 0/1 | none |
| delegate-residual | 1 | 5841 | 0 | 0 | unknown 0/1 | none |
| delegate-sweep | 2 | 6936 | 0 | 0 | unknown 0/2 | none |
| delta-coder | 1 | 7719 | 21435 | 1 | unknown 1/1 | karpathy-guidelines 1, superpowers:receiving-code-review 1, superpowers:test-driven-development 1, superpowers:verification-before-completion 1 |
| delta-live | 1 | 7224 | 9515 | 1 | unknown 0/1 | superpowers:systematic-debugging 1 |
| delta-reviewer | 1 | 6806 | 0 | 0 | T3 0/1 | none |
| deploy-fix7 | 1 | 5171 | 0 | 0 | unknown 0/1 | none |
| deploy-postsession | 1 | 4422 | 0 | 0 | unknown 0/1 | none |
| design-data-coder | 1 | 7267 | 21435 | 1 | unknown 1/1 | karpathy-guidelines 1, superpowers:receiving-code-review 1, superpowers:test-driven-development 1, superpowers:verification-before-completion 1 |
| design-policy-probe | 1 | 5543 | 0 | 0 | unknown 0/1 | none |
| dilemma-audit | 1 | 6615 | 0 | 0 | unknown 0/1 | none |
| dilemma-determinism | 1 | 5810 | 0 | 0 | unknown 0/1 | none |
| dilemma-probe | 1 | 5303 | 0 | 0 | unknown 0/1 | none |
| dilemma-sweep | 1 | 7374 | 0 | 0 | unknown 0/1 | none |
| dotnet-coder | 140 | 7657 | 13621 | 94 | T1 0/1, T2 8/15, T3 14/24, T4 1/2, unknown 67/98 | superpowers:test-driven-development 90, karpathy-guidelines 82, superpowers:receiving-code-review 79, superpowers:verification-before-completion 79, superpowers:systematic-debugging 8 |
| driver-weekend | 1 | 5942 | 0 | 0 | unknown 0/1 | none |
| driver-wire | 1 | 6598 | 0 | 0 | unknown 0/1 | none |
| e2e | 1 | 6366 | 0 | 0 | unknown 0/1 | none |
| explore-driver | 1 | 4340 | 0 | 0 | unknown 0/1 | none |
| explore-m21 | 1 | 4627 | 0 | 0 | unknown 0/1 | none |
| explore-m22-driver | 1 | 4939 | 0 | 0 | unknown 0/1 | none |
| explore-m23-plugin | 1 | 4231 | 0 | 0 | unknown 0/1 | none |
| explore-plugin | 1 | 4493 | 0 | 0 | unknown 0/1 | none |
| final-gate | 1 | 4738 | 0 | 0 | unknown 0/1 | none |
| fit-endpoint-probe | 1 | 5896 | 0 | 0 | unknown 0/1 | none |
| fitbest-zero | 1 | 5435 | 0 | 0 | unknown 0/1 | none |
| floor-challenger | 1 | 6417 | 0 | 0 | unknown 0/1 | none |
| floor-coder | 1 | 7842 | 21435 | 1 | unknown 1/1 | karpathy-guidelines 1, superpowers:receiving-code-review 1, superpowers:test-driven-development 1, superpowers:verification-before-completion 1 |
| floor-live | 1 | 6639 | 0 | 0 | unknown 0/1 | none |
| floor-probe | 1 | 5816 | 0 | 0 | unknown 0/1 | none |
| gamemodel-recon | 1 | 7419 | 0 | 0 | unknown 0/1 | none |
| gamestate-pause-trace | 1 | 8424 | 0 | 0 | unknown 0/1 | none |
| gap-rank | 1 | 5394 | 0 | 0 | unknown 0/1 | none |
| gap-rank-2 | 1 | 5355 | 0 | 0 | unknown 0/1 | none |
| gate-133cf39 | 1 | 4218 | 0 | 0 | unknown 0/1 | none |
| gate-doctor | 1 | 5765 | 0 | 0 | unknown 0/1 | none |
| gate-final2 | 1 | 4187 | 0 | 0 | unknown 0/1 | none |
| gate-m38-final | 1 | 4434 | 0 | 0 | unknown 0/1 | none |
| gate-m39-live | 1 | 4236 | 0 | 0 | unknown 0/1 | none |
| gate-main-m38 | 1 | 4351 | 0 | 0 | unknown 0/1 | none |
| gate-reader | 1 | 5860 | 0 | 0 | unknown 0/1 | none |
| gate-solver | 1 | 4010 | 0 | 0 | unknown 0/1 | none |
| gate-verify | 1 | 4790 | 0 | 0 | unknown 0/1 | none |
| general-purpose | 243 | 5626 | 3831 | 44 | T1 0/1, T2 6/8, unknown 34/234 | karpathy-guidelines 41, superpowers:test-driven-development 40, superpowers:verification-before-completion 38, superpowers:receiving-code-review 31, superpowers:systematic-debugging 2 |
| gitignore-fix | 1 | 5390 | 0 | 0 | unknown 0/1 | none |
| gma-decomp | 1 | 7475 | 0 | 0 | unknown 0/1 | none |
| goal-run-10 | 1 | 7955 | 0 | 0 | unknown 0/1 | none |
| goal-run-6 | 1 | 8212 | 0 | 0 | unknown 0/1 | none |
| goal-run-7 | 1 | 8658 | 0 | 0 | unknown 0/1 | none |
| goal-run-9 | 1 | 7525 | 0 | 0 | unknown 0/1 | none |
| goal-run-9-adopt | 1 | 7976 | 0 | 0 | unknown 0/1 | none |
| guide-md | 1 | 6674 | 0 | 0 | unknown 0/1 | none |
| guide-pdf | 1 | 6721 | 0 | 0 | unknown 0/1 | none |
| hire-cost | 1 | 7010 | 0 | 0 | unknown 0/1 | none |
| hub-audit | 1 | 7126 | 0 | 0 | unknown 0/1 | none |
| hub-recon | 1 | 6557 | 0 | 0 | unknown 0/1 | none |
| improve-probe | 1 | 5722 | 0 | 0 | unknown 0/1 | none |
| improve-rate | 1 | 6510 | 0 | 0 | unknown 0/1 | none |
| improve-split-probe | 1 | 4771 | 0 | 0 | unknown 0/1 | none |
| inframe-sweep | 1 | 7484 | 7103 | 1 | unknown 0/1 | superpowers:writing-plans 1 |
| inframe-sweep-10 | 1 | 6580 | 0 | 0 | unknown 0/1 | none |
| inframe-sweep-2 | 1 | 7073 | 0 | 0 | unknown 0/1 | none |
| inframe-sweep-3 | 1 | 6291 | 0 | 0 | unknown 0/1 | none |
| inframe-sweep-4 | 1 | 6572 | 0 | 0 | unknown 0/1 | none |
| inframe-sweep-5 | 1 | 6405 | 0 | 0 | unknown 0/1 | none |
| inframe-sweep-6 | 1 | 6598 | 0 | 0 | unknown 0/1 | none |
| inframe-sweep-7 | 1 | 6416 | 0 | 0 | unknown 0/1 | none |
| inframe-sweep-8 | 1 | 6698 | 0 | 0 | unknown 0/1 | none |
| inframe-sweep-9 | 1 | 6110 | 0 | 0 | unknown 0/1 | none |
| inv-stale | 1 | 4699 | 0 | 0 | unknown 0/1 | none |
| laptime-gap | 1 | 5530 | 0 | 0 | unknown 0/1 | none |
| leverage-analysis | 1 | 7040 | 7103 | 1 | unknown 0/1 | superpowers:writing-plans 1 |
| live-reads | 1 | 6787 | 0 | 0 | unknown 0/1 | none |
| live-verify-reads | 1 | 7374 | 0 | 0 | unknown 0/1 | none |
| live-verify-writes | 1 | 6641 | 0 | 0 | unknown 0/1 | none |
| liveness-audit | 1 | 6210 | 0 | 0 | unknown 0/1 | none |
| longrun-m60b | 1 | 6449 | 0 | 0 | unknown 0/1 | none |
| m10-coder | 1 | 7210 | 0 | 0 | unknown 0/1 | none |
| m10-reviewer | 1 | 5226 | 0 | 0 | unknown 0/1 | none |
| m10-tester | 1 | 4858 | 0 | 0 | unknown 0/1 | none |
| m10b-coder | 1 | 5494 | 0 | 0 | unknown 0/1 | none |
| m10b-reviewer | 1 | 4166 | 0 | 0 | unknown 0/1 | none |
| m10c-coder | 1 | 4759 | 0 | 0 | T1 0/1 | none |
| m11-coder | 1 | 4711 | 0 | 0 | unknown 0/1 | none |
| m11-reviewer | 1 | 4769 | 0 | 0 | unknown 0/1 | none |
| m12-reviewer | 1 | 5680 | 0 | 0 | unknown 0/1 | none |
| m12-tester | 1 | 4883 | 0 | 0 | unknown 0/1 | none |
| m12-wsa | 1 | 6900 | 0 | 0 | unknown 0/1 | none |
| m12-wsb | 1 | 7210 | 0 | 0 | unknown 0/1 | none |
| m13-architect | 1 | 5434 | 0 | 0 | T3 0/1 | none |
| m13-coder | 1 | 8740 | 0 | 0 | unknown 0/1 | none |
| m13-reviewer | 1 | 6697 | 0 | 0 | unknown 0/1 | none |
| m13-tester | 1 | 4792 | 0 | 0 | unknown 0/1 | none |
| m14-architect | 1 | 5522 | 0 | 0 | T3 0/1 | none |
| m14-coder | 1 | 9013 | 0 | 0 | unknown 0/1 | none |
| m14-reviewer | 1 | 6216 | 0 | 0 | unknown 0/1 | none |
| m14-tester | 1 | 4638 | 0 | 0 | unknown 0/1 | none |
| m15-coder | 1 | 6328 | 0 | 0 | unknown 0/1 | none |
| m15-reviewer | 1 | 4944 | 0 | 0 | unknown 0/1 | none |
| m16-coder | 1 | 6250 | 0 | 0 | unknown 0/1 | none |
| m16-reviewer | 1 | 5666 | 0 | 0 | unknown 0/1 | none |
| m17-architect | 1 | 5414 | 0 | 0 | T3 0/1 | none |
| m17-coder | 1 | 7501 | 0 | 0 | unknown 0/1 | none |
| m17-reviewer | 1 | 6184 | 0 | 0 | unknown 0/1 | none |
| m17-tester | 1 | 4743 | 0 | 0 | unknown 0/1 | none |
| m18-coder | 1 | 6043 | 0 | 0 | unknown 0/1 | none |
| m18-reviewer | 1 | 4968 | 0 | 0 | unknown 0/1 | none |
| m19-coder | 1 | 6305 | 159 | 1 | unknown 0/1 | karpathy-guidelines 1 |
| m19-reviewer | 1 | 5302 | 0 | 0 | unknown 0/1 | none |
| m20-architect | 1 | 6358 | 0 | 0 | T4 0/1 | none |
| m20-coder | 1 | 7234 | 159 | 1 | unknown 0/1 | superpowers:receiving-code-review 1 |
| m20-ops-gate | 1 | 2977 | 0 | 0 | unknown 0/1 | none |
| m20-reviewer | 1 | 5466 | 0 | 0 | unknown 0/1 | none |
| m20-tester | 1 | 5011 | 0 | 0 | unknown 0/1 | none |
| m21-architect | 1 | 5301 | 0 | 0 | T3 0/1 | none |
| m21-coder | 1 | 6100 | 0 | 0 | unknown 0/1 | none |
| m21-ops-gate | 1 | 3177 | 0 | 0 | unknown 0/1 | none |
| m21-reviewer | 1 | 5142 | 0 | 0 | unknown 0/1 | none |
| m21-tester | 1 | 4575 | 0 | 0 | unknown 0/1 | none |
| m22-architect | 1 | 5534 | 0 | 0 | T3 0/1 | none |
| m22-coder | 1 | 5493 | 0 | 0 | unknown 0/1 | none |
| m22-reviewer | 1 | 5409 | 0 | 0 | unknown 0/1 | none |
| m22-tester | 1 | 5116 | 0 | 0 | unknown 0/1 | none |
| m23-architect | 1 | 5798 | 0 | 0 | T4 0/1 | none |
| m23-coder | 1 | 6552 | 159 | 1 | unknown 0/1 | superpowers:receiving-code-review 1 |
| m23-ops-decompile | 1 | 4509 | 0 | 0 | unknown 0/1 | none |
| m23-reviewer | 1 | 5268 | 0 | 0 | unknown 0/1 | none |
| m23-tester | 1 | 4936 | 0 | 0 | unknown 0/1 | none |
| m24-coder | 1 | 4730 | 0 | 0 | unknown 0/1 | none |
| m24-reviewer | 1 | 4505 | 0 | 0 | unknown 0/1 | none |
| m25-coder | 1 | 6498 | 318 | 1 | unknown 0/1 |  2 |
| m25-gate-ops | 1 | 3956 | 0 | 0 | unknown 0/1 | none |
| m25-reviewer | 1 | 5740 | 0 | 0 | unknown 0/1 | none |
| m25dev | 1 | 9611 | 12631 | 1 | unknown 1/1 | karpathy-guidelines 1, superpowers:test-driven-development 1 |
| m26-coder | 1 | 6862 | 0 | 0 | unknown 0/1 | none |
| m26-gate-ops | 1 | 4083 | 0 | 0 | unknown 0/1 | none |
| m26-reviewer | 1 | 6013 | 0 | 0 | unknown 0/1 | none |
| m27-coder | 1 | 7059 | 0 | 0 | unknown 0/1 | none |
| m27-gate-ops | 1 | 4365 | 0 | 0 | unknown 0/1 | none |
| m27-label-coder | 1 | 6058 | 0 | 0 | unknown 0/1 | none |
| m27-reviewer | 1 | 5152 | 0 | 0 | unknown 0/1 | none |
| m28-coder | 1 | 6513 | 0 | 0 | unknown 0/1 | none |
| m28-gate-ops | 1 | 4358 | 0 | 0 | unknown 0/1 | none |
| m28-reviewer | 1 | 5174 | 0 | 0 | unknown 0/1 | none |
| m29-architect | 1 | 8433 | 0 | 0 | T4 0/1 | none |
| m29-coder | 1 | 8876 | 0 | 0 | unknown 0/1 | none |
| m291-architect | 1 | 6921 | 0 | 0 | unknown 0/1 | none |
| m291-coder | 1 | 7367 | 795 | 1 | unknown 1/1 | karpathy-guidelines 1, superpowers:receiving-code-review 1, superpowers:systematic-debugging 1, superpowers:test-driven-development 1, superpowers:verification-before-completion 1 |
| m2architect | 1 | 6345 | 0 | 0 | T3 0/1 | none |
| m2dev | 1 | 9304 | 4127 | 1 | unknown 0/1 | superpowers:verification-before-completion 1 |
| m2reviewer | 1 | 4944 | 0 | 0 | unknown 0/1 | none |
| m30-architect | 1 | 6293 | 0 | 0 | unknown 0/1 | none |
| m30-coder | 1 | 6809 | 159 | 1 | unknown 0/1 |  1 |
| m30-ops | 1 | 5440 | 0 | 0 | unknown 0/1 | none |
| m31-architect | 1 | 6725 | 0 | 0 | unknown 0/1 | none |
| m31-coder | 1 | 6011 | 0 | 0 | T4 0/1 | none |
| m31-fixer | 1 | 7217 | 0 | 0 | unknown 0/1 | none |
| m31-gate | 1 | 4077 | 0 | 0 | unknown 0/1 | none |
| m31-ops | 1 | 3451 | 0 | 0 | unknown 0/1 | none |
| m31-ops2 | 1 | 5470 | 0 | 0 | unknown 0/1 | none |
| m31-ops3 | 1 | 5166 | 0 | 0 | unknown 0/1 | none |
| m31-ops4 | 1 | 4469 | 0 | 0 | unknown 0/1 | none |
| m31-results | 1 | 6323 | 0 | 0 | unknown 0/1 | none |
| m33-fixer | 1 | 5961 | 0 | 0 | unknown 0/1 | none |
| m33-gate | 1 | 3713 | 0 | 0 | unknown 0/1 | none |
| m33-validate | 1 | 4334 | 0 | 0 | unknown 0/1 | none |
| m34-fix | 1 | 6576 | 0 | 0 | unknown 0/1 | none |
| m34-fix2 | 1 | 6421 | 0 | 0 | unknown 0/1 | none |
| m34-recon | 1 | 6471 | 0 | 0 | unknown 0/1 | none |
| m34-validate | 1 | 5503 | 0 | 0 | unknown 0/1 | none |
| m34-wk1 | 1 | 4480 | 0 | 0 | unknown 0/1 | none |
| m34-wk2 | 1 | 5257 | 0 | 0 | unknown 0/1 | none |
| m34-wk3 | 1 | 4991 | 0 | 0 | unknown 0/1 | none |
| m35-batchB | 1 | 4664 | 0 | 0 | unknown 0/1 | none |
| m35-batchC | 1 | 4531 | 0 | 0 | unknown 0/1 | none |
| m35-treatment | 1 | 5767 | 0 | 0 | unknown 0/1 | none |
| m36-batchD | 1 | 4892 | 0 | 0 | unknown 0/1 | none |
| m36-batchE | 1 | 4515 | 0 | 0 | unknown 0/1 | none |
| m36-flag | 1 | 5395 | 0 | 0 | unknown 0/1 | none |
| m36-gate | 1 | 3237 | 0 | 0 | unknown 0/1 | none |
| m37-coder | 1 | 7513 | 0 | 0 | unknown 0/1 | none |
| m37-regate | 1 | 4390 | 0 | 0 | unknown 0/1 | none |
| m37-reviewer | 1 | 6273 | 0 | 0 | unknown 0/1 | none |
| m38-fix1 | 1 | 6918 | 0 | 0 | unknown 0/1 | none |
| m38-fix2 | 1 | 7377 | 0 | 0 | unknown 0/1 | none |
| m38-fix3 | 1 | 8233 | 0 | 0 | unknown 0/1 | none |
| m38-fix4 | 1 | 7844 | 318 | 1 | unknown 0/1 | karpathy-guidelines 1, superpowers:verification-before-completion 1 |
| m38-fix6 | 1 | 7876 | 0 | 0 | unknown 0/1 | none |
| m38-fix7 | 1 | 7522 | 0 | 0 | unknown 0/1 | none |
| m38-fix8 | 1 | 9143 | 0 | 0 | unknown 0/1 | none |
| m39-finish | 1 | 8305 | 0 | 0 | unknown 0/1 | none |
| m39-live-practice | 1 | 6620 | 0 | 0 | unknown 0/1 | none |
| m39-observe | 1 | 6548 | 0 | 0 | unknown 0/1 | none |
| m39-postsession | 1 | 6738 | 0 | 0 | unknown 0/1 | none |
| m39-setup-apply | 1 | 7155 | 0 | 0 | unknown 0/1 | none |
| m39-setup-write | 1 | 6919 | 0 | 0 | unknown 0/1 | none |
| m39-solver | 1 | 7192 | 0 | 0 | unknown 0/1 | none |
| m3912-coder | 1 | 5702 | 0 | 0 | unknown 0/1 | none |
| m3912-gate | 1 | 4680 | 0 | 0 | unknown 0/1 | none |
| m3912-livecheck | 1 | 6015 | 0 | 0 | unknown 0/1 | none |
| m399-coder | 1 | 6536 | 159 | 1 | unknown 0/1 |  1 |
| m399-ops | 1 | 6695 | 0 | 0 | unknown 0/1 | none |
| m3architect | 1 | 5975 | 0 | 0 | unknown 0/1 | none |
| m3dev | 1 | 8977 | 0 | 0 | unknown 0/1 | none |
| m3reviewer | 1 | 5095 | 0 | 0 | unknown 0/1 | none |
| m4-fixup | 1 | 5299 | 0 | 0 | unknown 0/1 | none |
| m4-nullfix | 1 | 6070 | 0 | 0 | unknown 0/1 | none |
| m4-reviewer | 1 | 5492 | 0 | 0 | unknown 0/1 | none |
| m4-tester | 1 | 4502 | 0 | 0 | unknown 0/1 | none |
| m40-autosave | 1 | 7560 | 0 | 0 | unknown 0/1 | none |
| m40-calendar | 1 | 7840 | 0 | 0 | unknown 0/1 | none |
| m40-career-entry | 1 | 5459 | 0 | 0 | unknown 0/1 | none |
| m40-career-load | 1 | 7451 | 0 | 0 | unknown 0/1 | none |
| m40-e2e | 1 | 6526 | 0 | 0 | unknown 0/1 | none |
| m40-ersrun | 1 | 6000 | 0 | 0 | unknown 0/1 | none |
| m40-infra | 1 | 7155 | 0 | 0 | unknown 0/1 | none |
| m40-observe | 1 | 6275 | 0 | 0 | unknown 0/1 | none |
| m40-quickrace | 1 | 5989 | 0 | 0 | unknown 0/1 | none |
| m40-raceentry | 1 | 7742 | 0 | 0 | unknown 0/1 | none |
| m40-savebackup | 1 | 4608 | 0 | 0 | unknown 0/1 | none |
| m40-speedtest | 1 | 6313 | 0 | 0 | unknown 0/1 | none |
| m40-weekend | 1 | 7695 | 0 | 0 | unknown 0/1 | none |
| m41-qualifying | 1 | 7432 | 0 | 0 | unknown 0/1 | none |
| m41-qualloop | 1 | 7051 | 0 | 0 | unknown 0/1 | none |
| m41-racesetup | 1 | 7006 | 0 | 0 | unknown 0/1 | none |
| m41-season | 1 | 7744 | 0 | 0 | unknown 0/1 | none |
| m42-budget | 1 | 9580 | 0 | 0 | unknown 0/1 | none |
| m42-commission | 1 | 8023 | 0 | 0 | unknown 0/1 | none |
| m42-components | 1 | 9524 | 0 | 0 | unknown 0/1 | none |
| m42-observe | 1 | 7586 | 0 | 0 | unknown 0/1 | none |
| m42-part | 1 | 7652 | 0 | 0 | unknown 0/1 | none |
| m43-devloop | 1 | 9179 | 21435 | 1 | unknown 1/1 | karpathy-guidelines 1, superpowers:receiving-code-review 1, superpowers:test-driven-development 1, superpowers:verification-before-completion 1 |
| m43-improve | 1 | 7624 | 0 | 0 | unknown 0/1 | none |
| m43-improve-impl | 1 | 9389 | 21435 | 1 | unknown 1/1 | karpathy-guidelines 1, superpowers:receiving-code-review 1, superpowers:test-driven-development 1, superpowers:verification-before-completion 1 |
| m43-levers | 1 | 7200 | 0 | 0 | unknown 0/1 | none |
| m43-origin | 1 | 8318 | 21435 | 1 | unknown 1/1 | karpathy-guidelines 1, superpowers:receiving-code-review 1, superpowers:test-driven-development 1, superpowers:verification-before-completion 1 |
| m43-rollover | 1 | 8475 | 21435 | 1 | unknown 1/1 | karpathy-guidelines 1, superpowers:receiving-code-review 1, superpowers:test-driven-development 1, superpowers:verification-before-completion 1 |
| m44-ballot | 1 | 6933 | 9515 | 1 | unknown 0/1 | superpowers:systematic-debugging 1 |
| m44-liveread | 1 | 6332 | 9515 | 1 | unknown 0/1 | superpowers:systematic-debugging 1 |
| m44-politics | 1 | 8470 | 21435 | 1 | T3 1/1 | karpathy-guidelines 1, superpowers:receiving-code-review 1, superpowers:test-driven-development 1, superpowers:verification-before-completion 1 |
| m44-staleverify | 1 | 7094 | 9515 | 1 | unknown 0/1 | superpowers:systematic-debugging 1 |
| m44-state | 1 | 8426 | 21435 | 1 | T3 1/1 | karpathy-guidelines 1, superpowers:receiving-code-review 1, superpowers:test-driven-development 1, superpowers:verification-before-completion 1 |
| m45-beijingrace | 1 | 5791 | 0 | 0 | unknown 0/1 | none |
| m45-httpfix | 1 | 7459 | 21435 | 1 | unknown 1/1 | karpathy-guidelines 1, superpowers:receiving-code-review 1, superpowers:test-driven-development 1, superpowers:verification-before-completion 1 |
| m45-pacefix | 1 | 9294 | 21435 | 1 | unknown 1/1 | karpathy-guidelines 1, superpowers:receiving-code-review 1, superpowers:test-driven-development 1, superpowers:verification-before-completion 1 |
| m45-portmove | 1 | 7239 | 21435 | 1 | unknown 1/1 | karpathy-guidelines 1, superpowers:receiving-code-review 1, superpowers:test-driven-development 1, superpowers:verification-before-completion 1 |
| m45-regate | 1 | 6565 | 21435 | 1 | unknown 1/1 | karpathy-guidelines 1, superpowers:receiving-code-review 1, superpowers:test-driven-development 1, superpowers:verification-before-completion 1 |
| m45-season | 1 | 7936 | 9515 | 1 | unknown 0/1 | superpowers:systematic-debugging 1 |
| m46-marketread | 1 | 7065 | 9515 | 1 | unknown 0/1 | superpowers:systematic-debugging 1 |
| m46-merger | 1 | 5815 | 0 | 0 | unknown 0/1 | none |
| m46-ranked | 1 | 6891 | 13087 | 1 | unknown 0/1 | superpowers:systematic-debugging 1, superpowers:verification-before-completion 1 |
| m46-staffread | 1 | 8184 | 21435 | 1 | unknown 1/1 | karpathy-guidelines 1, superpowers:receiving-code-review 1, superpowers:test-driven-development 1, superpowers:verification-before-completion 1 |
| m47-live | 1 | 6405 | 0 | 0 | unknown 0/1 | none |
| m47-reviewer | 1 | 6869 | 0 | 0 | unknown 0/1 | none |
| m47-savefix | 1 | 7529 | 21870 | 1 | unknown 0/1 | karpathy-guidelines 1, superpowers:receiving-code-review 1, superpowers:systematic-debugging 1, superpowers:verification-before-completion 1 |
| m47-season | 1 | 6546 | 13087 | 1 | unknown 0/1 | superpowers:systematic-debugging 1, superpowers:verification-before-completion 1 |
| m47b-season | 1 | 6928 | 9515 | 1 | unknown 0/1 | superpowers:systematic-debugging 1 |
| m48-challenger | 1 | 7190 | 7103 | 1 | unknown 0/1 | superpowers:writing-plans 1 |
| m48-live | 1 | 6550 | 9515 | 1 | unknown 0/1 | superpowers:systematic-debugging 1 |
| m48-planner | 1 | 7093 | 30950 | 1 | unknown 1/1 | karpathy-guidelines 1, superpowers:receiving-code-review 1, superpowers:systematic-debugging 1, superpowers:test-driven-development 1, superpowers:verification-before-completion 1 |
| m48-reviewer | 1 | 7239 | 0 | 0 | unknown 0/1 | none |
| m49-challenger | 1 | 7068 | 7103 | 1 | unknown 0/1 | superpowers:writing-plans 1 |
| m49-live2 | 1 | 7486 | 0 | 0 | unknown 0/1 | none |
| m49a-reviewer | 1 | 6915 | 0 | 0 | unknown 0/1 | none |
| m49b-reviewer | 1 | 6622 | 0 | 0 | unknown 0/1 | none |
| m4architect | 1 | 6206 | 0 | 0 | unknown 0/1 | none |
| m5-fixup | 1 | 4940 | 0 | 0 | unknown 0/1 | none |
| m5-reviewer | 1 | 5127 | 0 | 0 | unknown 0/1 | none |
| m5-tester | 1 | 4482 | 0 | 0 | unknown 0/1 | none |
| m50-challenger | 1 | 6925 | 7103 | 1 | unknown 0/1 | superpowers:writing-plans 1 |
| m50-liveverify | 1 | 7227 | 9515 | 1 | unknown 0/1 | superpowers:systematic-debugging 1 |
| m50-reviewer | 1 | 7375 | 0 | 0 | unknown 0/1 | none |
| m51-challenger | 1 | 6631 | 7103 | 1 | unknown 0/1 | superpowers:writing-plans 1 |
| m51-review | 1 | 6271 | 0 | 0 | T2 0/1 | none |
| m52-reviewer | 1 | 6801 | 0 | 0 | unknown 0/1 | none |
| m53-challenger | 1 | 6249 | 7103 | 1 | unknown 0/1 | superpowers:writing-plans 1 |
| m56-challenge | 1 | 6027 | 0 | 0 | unknown 0/1 | none |
| m56-coder | 1 | 7310 | 21435 | 1 | unknown 1/1 | karpathy-guidelines 1, superpowers:receiving-code-review 1, superpowers:test-driven-development 1, superpowers:verification-before-completion 1 |
| m56-rollover | 1 | 6479 | 0 | 0 | unknown 0/1 | none |
| m57-challenge | 1 | 6748 | 7103 | 1 | unknown 0/1 | superpowers:writing-plans 1 |
| m57-coder | 1 | 7887 | 21435 | 1 | unknown 1/1 | karpathy-guidelines 1, superpowers:receiving-code-review 1, superpowers:test-driven-development 1, superpowers:verification-before-completion 1 |
| m58-challenge | 1 | 6606 | 0 | 0 | T2 0/1 | none |
| m58-coder | 1 | 7953 | 21435 | 1 | unknown 1/1 | karpathy-guidelines 1, superpowers:receiving-code-review 1, superpowers:test-driven-development 1, superpowers:verification-before-completion 1 |
| m58-resurvey | 1 | 6831 | 0 | 0 | unknown 0/1 | none |
| m59-challenge | 1 | 6577 | 7103 | 1 | T3 0/1 | superpowers:writing-plans 1 |
| m59-coder | 1 | 7307 | 0 | 0 | unknown 0/1 | none |
| m59-live | 1 | 6361 | 9515 | 1 | unknown 0/1 | superpowers:systematic-debugging 1 |
| m5architect | 1 | 7587 | 0 | 0 | unknown 0/1 | none |
| m6-fixup | 1 | 4946 | 0 | 0 | unknown 0/1 | none |
| m6-reviewer | 1 | 5539 | 0 | 0 | unknown 0/1 | none |
| m6-tester | 1 | 4225 | 0 | 0 | unknown 0/1 | none |
| m60-rollover2 | 1 | 8784 | 0 | 0 | unknown 0/1 | none |
| m60a-coder | 1 | 7370 | 0 | 0 | unknown 0/1 | none |
| m60b-challenge | 1 | 6968 | 7103 | 1 | T3 0/1 | superpowers:writing-plans 1 |
| m60b-coder | 1 | 7331 | 21435 | 1 | unknown 1/1 | karpathy-guidelines 1, superpowers:receiving-code-review 1, superpowers:test-driven-development 1, superpowers:verification-before-completion 1 |
| m60b-finisher | 1 | 5261 | 0 | 0 | unknown 0/1 | none |
| m60b-live | 1 | 6581 | 0 | 0 | unknown 0/1 | none |
| m61-coder | 1 | 7289 | 21435 | 1 | unknown 1/1 | karpathy-guidelines 1, superpowers:receiving-code-review 1, superpowers:test-driven-development 1, superpowers:verification-before-completion 1 |
| m61-live | 1 | 6319 | 0 | 0 | unknown 0/1 | none |
| m62-challenge | 1 | 6452 | 7103 | 1 | T2 0/1 | superpowers:writing-plans 1 |
| m62-constraint | 1 | 6714 | 0 | 0 | unknown 0/1 | none |
| m62a-coder | 1 | 7735 | 21435 | 1 | unknown 1/1 | karpathy-guidelines 1, superpowers:receiving-code-review 1, superpowers:test-driven-development 1, superpowers:verification-before-completion 1 |
| m62a-finisher | 1 | 6062 | 0 | 0 | unknown 0/1 | none |
| m62a-fix-coder | 1 | 7296 | 21435 | 1 | unknown 1/1 | karpathy-guidelines 1, superpowers:receiving-code-review 1, superpowers:test-driven-development 1, superpowers:verification-before-completion 1 |
| m62a-fix-live | 1 | 6520 | 0 | 0 | unknown 0/1 | none |
| m62a-live | 1 | 6741 | 0 | 0 | unknown 0/1 | none |
| m63-adopt | 1 | 5864 | 0 | 0 | unknown 0/1 | none |
| m63-coder | 1 | 7025 | 21435 | 1 | unknown 1/1 | karpathy-guidelines 1, superpowers:receiving-code-review 1, superpowers:test-driven-development 1, superpowers:verification-before-completion 1 |
| m63-crashes | 1 | 7407 | 0 | 0 | unknown 0/1 | none |
| m63-live | 1 | 6398 | 0 | 0 | unknown 0/1 | none |
| m64-challenge | 1 | 6278 | 0 | 0 | T2 0/1 | none |
| m64-coder | 1 | 7239 | 0 | 0 | T2 0/1 | none |
| m64-crashexp | 1 | 6763 | 9515 | 1 | unknown 0/1 | superpowers:systematic-debugging 1 |
| m64-finisher | 1 | 6333 | 0 | 0 | T2 0/1 | none |
| m64-live | 1 | 6097 | 0 | 0 | unknown 0/1 | none |
| m64-merge | 1 | 5457 | 0 | 0 | unknown 0/1 | none |
| m65-challenge | 1 | 6744 | 7103 | 1 | T3 0/1 | superpowers:writing-plans 1 |
| m65-mutationhunt | 1 | 6515 | 0 | 0 | unknown 0/1 | none |
| m65-runner | 1 | 5922 | 0 | 0 | unknown 0/1 | none |
| m66-challenge | 1 | 6530 | 0 | 0 | unknown 0/1 | none |
| m66-finish | 1 | 5910 | 0 | 0 | unknown 0/1 | none |
| m66-review | 1 | 4753 | 0 | 0 | unknown 0/1 | none |
| m66-runner | 1 | 5882 | 0 | 0 | unknown 0/1 | none |
| m66-runner2 | 1 | 6888 | 0 | 0 | unknown 0/1 | none |
| m67-challenge | 1 | 6894 | 0 | 0 | unknown 0/1 | none |
| m68-challenge | 1 | 6871 | 0 | 0 | unknown 0/1 | none |
| m68-inprocess | 1 | 7253 | 6957 | 1 | unknown 0/1 | superpowers:writing-plans 1 |
| m69-challenge | 1 | 6400 | 0 | 0 | unknown 0/1 | none |
| m69-runner | 1 | 6042 | 0 | 0 | unknown 0/1 | none |
| m6architect | 1 | 6088 | 0 | 0 | unknown 0/1 | none |
| m7-fixup | 1 | 5030 | 0 | 0 | unknown 0/1 | none |
| m7-phase0 | 1 | 6993 | 0 | 0 | unknown 0/1 | none |
| m7-reviewer | 1 | 5401 | 0 | 0 | unknown 0/1 | none |
| m7-tester | 1 | 5266 | 0 | 0 | unknown 0/1 | none |
| m7-wsa | 1 | 9379 | 0 | 0 | unknown 0/1 | none |
| m7-wsb | 1 | 8792 | 0 | 0 | unknown 0/1 | none |
| m70-monoload | 1 | 5052 | 0 | 0 | unknown 0/1 | none |
| m70-runner | 1 | 6463 | 0 | 0 | unknown 0/1 | none |
| m71-boundary | 1 | 6527 | 0 | 0 | unknown 0/1 | none |
| m71-challenge | 1 | 6900 | 0 | 0 | unknown 0/1 | none |
| m71-gate | 1 | 6144 | 0 | 0 | unknown 0/1 | none |
| m71-verify | 1 | 6516 | 0 | 0 | unknown 0/1 | none |
| m72-challenge | 1 | 6654 | 7103 | 1 | unknown 0/1 | superpowers:writing-plans 1 |
| m72-gatecheck | 1 | 4794 | 0 | 0 | unknown 0/1 | none |
| m72a-runner | 1 | 6222 | 0 | 0 | unknown 0/1 | none |
| m72b1-runner | 1 | 6696 | 0 | 0 | unknown 0/1 | none |
| m73-challenge | 1 | 6305 | 7103 | 1 | unknown 0/1 | superpowers:writing-plans 1 |
| m74-challenge | 1 | 7102 | 0 | 0 | unknown 0/1 | none |
| m74-eventcheck | 1 | 5421 | 0 | 0 | unknown 0/1 | none |
| m74-runner | 1 | 6346 | 0 | 0 | unknown 0/1 | none |
| m75-challenge | 1 | 7444 | 7103 | 1 | unknown 0/1 | superpowers:writing-plans 1 |
| m75-runner | 1 | 6958 | 0 | 0 | unknown 0/1 | none |
| m76-fixture | 1 | 5624 | 0 | 0 | unknown 0/1 | none |
| m79-challenge | 1 | 7019 | 0 | 0 | unknown 0/1 | none |
| m8-coder | 1 | 5746 | 0 | 0 | unknown 0/1 | none |
| m8-reviewer | 1 | 5083 | 0 | 0 | unknown 0/1 | none |
| m82-challenge | 1 | 7423 | 7103 | 1 | unknown 0/1 | superpowers:writing-plans 1 |
| m83-challenge | 1 | 7423 | 7103 | 1 | unknown 0/1 | superpowers:writing-plans 1 |
| m83-live | 1 | 8521 | 0 | 0 | unknown 0/1 | none |
| m83-merge | 1 | 5408 | 0 | 0 | unknown 0/1 | none |
| m84-challenge | 1 | 7674 | 0 | 0 | unknown 0/1 | none |
| m84b-live | 1 | 7031 | 0 | 0 | unknown 0/1 | none |
| m85-challenge | 1 | 7414 | 7103 | 1 | unknown 0/1 | superpowers:writing-plans 1 |
| m86-diagnose | 1 | 7645 | 9515 | 1 | unknown 0/1 | superpowers:systematic-debugging 1 |
| m87-challenge | 1 | 7560 | 0 | 0 | unknown 0/1 | none |
| m87-finish | 1 | 5730 | 0 | 0 | unknown 0/1 | none |
| m87-live | 1 | 7975 | 0 | 0 | unknown 0/1 | none |
| m89-live | 1 | 5666 | 0 | 0 | unknown 0/1 | none |
| m9-coder | 1 | 5576 | 0 | 0 | unknown 0/1 | none |
| m9-reviewer | 1 | 4918 | 0 | 0 | unknown 0/1 | none |
| m91-challenge | 1 | 7413 | 0 | 0 | unknown 0/1 | none |
| m91-live | 1 | 7051 | 0 | 0 | unknown 0/1 | none |
| m92-challenge | 1 | 7396 | 0 | 0 | unknown 0/1 | none |
| m92-live | 1 | 6717 | 9515 | 1 | unknown 0/1 | superpowers:systematic-debugging 1 |
| mail-challenger | 1 | 6388 | 0 | 0 | T3 0/1 | none |
| main-gate | 1 | 4462 | 0 | 0 | unknown 0/1 | none |
| main-gate-2 | 1 | 4205 | 0 | 0 | unknown 0/1 | none |
| main-gate-3 | 1 | 4523 | 0 | 0 | unknown 0/1 | none |
| manager-census | 1 | 7702 | 7103 | 1 | unknown 0/1 | superpowers:writing-plans 1 |
| mechanic-type-lookup | 1 | 5211 | 0 | 0 | unknown 0/1 | none |
| methodgroup-sweep | 1 | 8294 | 0 | 0 | unknown 0/1 | none |
| mm-runner | 114 | 6242 | 501 | 9 | unknown 0/114 | superpowers:verification-before-completion 8, superpowers:systematic-debugging 3 |
| multiseason-runner | 1 | 6507 | 0 | 0 | unknown 0/1 | none |
| multiseason-runner2 | 1 | 6833 | 0 | 0 | unknown 0/1 | none |
| multiseason-runner3 | 1 | 6602 | 0 | 0 | unknown 0/1 | none |
| multiseason-runner4 | 1 | 9275 | 0 | 0 | unknown 0/1 | none |
| multiseason-runner5 | 1 | 6862 | 0 | 0 | unknown 0/1 | none |
| namespace-coder | 1 | 7468 | 21435 | 1 | unknown 1/1 | karpathy-guidelines 1, superpowers:receiving-code-review 1, superpowers:test-driven-development 1, superpowers:verification-before-completion 1 |
| objective-null | 1 | 6500 | 0 | 0 | unknown 0/1 | none |
| ops | 121 | 4670 | 295 | 10 | T1 0/3, unknown 0/118 | superpowers:verification-before-completion 10 |
| pause-coder | 1 | 6863 | 21435 | 1 | unknown 1/1 | karpathy-guidelines 1, superpowers:receiving-code-review 1, superpowers:test-driven-development 1, superpowers:verification-before-completion 1 |
| pause-live | 1 | 6313 | 13087 | 1 | unknown 0/1 | superpowers:systematic-debugging 1, superpowers:verification-before-completion 1 |
| perf-instrument | 1 | 7733 | 21435 | 1 | unknown 1/1 | karpathy-guidelines 1, superpowers:receiving-code-review 1, superpowers:test-driven-development 1, superpowers:verification-before-completion 1 |
| perslot-coder | 1 | 6988 | 21435 | 1 | unknown 1/1 | karpathy-guidelines 1, superpowers:receiving-code-review 1, superpowers:test-driven-development 1, superpowers:verification-before-completion 1 |
| perslot-live | 1 | 6454 | 0 | 0 | unknown 0/1 | none |
| pit-logic-probe | 1 | 5426 | 0 | 0 | unknown 0/1 | none |
| plan-challenger | 1 | 5927 | 7103 | 1 | T3 0/1 | superpowers:writing-plans 1 |
| plugin-diag | 1 | 6900 | 0 | 0 | unknown 0/1 | none |
| plugindev | 1 | 8791 | 6799 | 1 | unknown 0/1 | karpathy-guidelines 1, superpowers:verification-before-completion 1 |
| points-check | 1 | 6001 | 0 | 0 | unknown 0/1 | none |
| politics-challenger | 1 | 6368 | 0 | 0 | T3 0/1 | none |
| politics-coder | 1 | 7774 | 21435 | 1 | unknown 1/1 | karpathy-guidelines 1, superpowers:receiving-code-review 1, superpowers:test-driven-development 1, superpowers:verification-before-completion 1 |
| politics-finish | 1 | 7818 | 0 | 0 | unknown 0/1 | none |
| politics-route | 1 | 6401 | 0 | 0 | unknown 0/1 | none |
| pollfix | 1 | 6095 | 0 | 0 | unknown 0/1 | none |
| practice-probe | 1 | 4687 | 0 | 0 | unknown 0/1 | none |
| preseason-exit-probe | 1 | 7772 | 0 | 0 | unknown 0/1 | none |
| preseason-sequence-probe | 1 | 6943 | 0 | 0 | unknown 0/1 | none |
| preseason-test-clock | 1 | 7720 | 0 | 0 | unknown 0/1 | none |
| q3-fanout | 1 | 7096 | 0 | 0 | unknown 0/1 | none |
| qelim-crash | 1 | 6329 | 0 | 0 | unknown 0/1 | none |
| reachability | 1 | 5919 | 0 | 0 | unknown 0/1 | none |
| readyflag-recheck | 1 | 6303 | 0 | 0 | unknown 0/1 | none |
| recall-fix | 1 | 6770 | 0 | 0 | unknown 0/1 | none |
| recon-enum | 1 | 5695 | 0 | 0 | unknown 0/1 | none |
| recon-mechanics | 1 | 5818 | 0 | 0 | unknown 0/1 | none |
| reissue-probe | 1 | 6284 | 0 | 0 | unknown 0/1 | none |
| reliability-cost | 1 | 6552 | 9515 | 1 | unknown 0/1 | superpowers:systematic-debugging 1 |
| reliability-model | 1 | 5634 | 0 | 0 | unknown 0/1 | none |
| remote-setup | 1 | 5435 | 0 | 0 | unknown 0/1 | none |
| report-coder | 1 | 7239 | 21435 | 1 | unknown 1/1 | karpathy-guidelines 1, superpowers:receiving-code-review 1, superpowers:test-driven-development 1, superpowers:verification-before-completion 1 |
| report-reviewer | 1 | 6641 | 0 | 0 | unknown 0/1 | none |
| respond-challenger | 1 | 6370 | 0 | 0 | T3 0/1 | none |
| reviewer | 1 | 4899 | 0 | 0 | unknown 0/1 | none |
| role-sweep | 1 | 7829 | 0 | 0 | unknown 0/1 | none |
| rollover-probe | 1 | 6884 | 0 | 0 | unknown 0/1 | none |
| rollover-timing | 1 | 6216 | 0 | 0 | unknown 0/1 | none |
| rules-probe | 1 | 7016 | 0 | 0 | unknown 0/1 | none |
| run10-finish | 1 | 6386 | 0 | 0 | unknown 0/1 | none |
| saveloc-challenger | 1 | 5865 | 7103 | 1 | T2 0/1 | superpowers:writing-plans 1 |
| saveloc-coder-2 | 1 | 7840 | 21435 | 1 | unknown 1/1 | karpathy-guidelines 1, superpowers:receiving-code-review 1, superpowers:test-driven-development 1, superpowers:verification-before-completion 1 |
| scalar-solve | 1 | 6879 | 0 | 0 | unknown 0/1 | none |
| scout-challenger | 1 | 6742 | 0 | 0 | T2 0/1 | none |
| scrutineer-probe | 1 | 5919 | 0 | 0 | unknown 0/1 | none |
| season-finish | 1 | 6855 | 0 | 0 | unknown 0/1 | none |
| season-run | 1 | 6821 | 0 | 0 | unknown 0/1 | none |
| serializer-probe | 1 | 6602 | 0 | 0 | unknown 0/1 | none |
| serializer-probe-2 | 1 | 5919 | 0 | 0 | unknown 0/1 | none |
| series-and-fixtures | 1 | 8100 | 0 | 0 | unknown 0/1 | none |
| session-start-differential | 1 | 8245 | 0 | 0 | unknown 0/1 | none |
| sessions-coder | 1 | 5718 | 0 | 0 | unknown 0/1 | none |
| setupcap | 1 | 6955 | 0 | 0 | unknown 0/1 | none |
| sign-challenger | 1 | 5963 | 7103 | 1 | T3 0/1 | superpowers:writing-plans 1 |
| signal-authority | 1 | 6219 | 7103 | 1 | unknown 0/1 | superpowers:writing-plans 1 |
| split-challenger | 1 | 6561 | 0 | 0 | unknown 0/1 | none |
| split-coder | 1 | 8371 | 21574 | 1 | unknown 1/1 | superpowers:receiving-code-review 2, karpathy-guidelines 1, superpowers:test-driven-development 1, superpowers:verification-before-completion 1 |
| split-discriminator | 1 | 5871 | 0 | 0 | unknown 0/1 | none |
| split-live | 1 | 7794 | 0 | 0 | unknown 0/1 | none |
| split-pricer | 1 | 6933 | 7103 | 1 | unknown 0/1 | superpowers:writing-plans 1 |
| split-probe | 1 | 5449 | 0 | 0 | unknown 0/1 | none |
| split-reviewer | 1 | 6995 | 0 | 0 | unknown 0/1 | none |
| split-tester | 1 | 6557 | 13087 | 1 | unknown 0/1 | superpowers:systematic-debugging 1, superpowers:verification-before-completion 1 |
| sponsor-challenger | 1 | 6597 | 0 | 0 | T3 0/1 | none |
| sponsor-path | 1 | 7338 | 0 | 0 | unknown 0/1 | none |
| spread-read | 1 | 6396 | 9515 | 1 | unknown 0/1 | superpowers:systematic-debugging 1 |
| staff-market | 1 | 7426 | 0 | 0 | unknown 0/1 | none |
| stage-d-live | 1 | 6618 | 0 | 0 | unknown 0/1 | none |
| stale-read-probe | 1 | 5550 | 0 | 0 | unknown 0/1 | none |
| status-probe | 1 | 6357 | 0 | 0 | unknown 0/1 | none |
| surface-audit | 2 | 8037 | 3551 | 1 | unknown 0/2 | superpowers:writing-plans 1 |
| surface-audit-2 | 1 | 7881 | 7103 | 1 | unknown 0/1 | superpowers:writing-plans 1 |
| t2-challenger | 1 | 6610 | 0 | 0 | unknown 0/1 | none |
| target-sweep | 1 | 7784 | 0 | 0 | unknown 0/1 | none |
| test-triage | 1 | 5295 | 0 | 0 | unknown 0/1 | none |
| tester | 4 | 5942 | 14464 | 4 | unknown 1/4 | superpowers:systematic-debugging 4, superpowers:verification-before-completion 3, superpowers:test-driven-development 1 |
| tier1-measure | 1 | 6192 | 0 | 0 | unknown 0/1 | none |
| travel-skip-scope | 1 | 7188 | 0 | 0 | unknown 0/1 | none |
| tyre-challenger | 1 | 6133 | 0 | 0 | T3 0/1 | none |
| tyre-crash-trace | 1 | 7300 | 0 | 0 | unknown 0/1 | none |
| uidev | 1 | 7046 | 0 | 0 | unknown 0/1 | none |
| value-live | 1 | 6418 | 0 | 0 | unknown 0/1 | none |
| value-order-coder | 1 | 7877 | 31089 | 1 | unknown 1/1 | superpowers:receiving-code-review 2, karpathy-guidelines 1, superpowers:systematic-debugging 1, superpowers:test-driven-development 1, superpowers:verification-before-completion 1 |
| verify-3rows | 1 | 7022 | 9515 | 1 | unknown 0/1 | superpowers:systematic-debugging 1 |
| vote-eligibility | 1 | 7478 | 0 | 0 | unknown 0/1 | none |
| votes-catalogue | 1 | 7346 | 0 | 0 | unknown 0/1 | none |
| wear-rate-live | 1 | 6536 | 9515 | 1 | unknown 0/1 | superpowers:systematic-debugging 1 |
| weekend-race-2 | 1 | 4367 | 0 | 0 | unknown 0/1 | none |
| weekend-race-3 | 1 | 4904 | 0 | 0 | unknown 0/1 | none |
| weekend-race-run | 1 | 4629 | 0 | 0 | unknown 0/1 | none |
| weekend-retest | 1 | 6526 | 0 | 0 | unknown 0/1 | none |
| weekend-tester | 1 | 6576 | 0 | 0 | unknown 0/1 | none |
| whatif-coder | 1 | 8467 | 21435 | 1 | unknown 1/1 | karpathy-guidelines 1, superpowers:receiving-code-review 1, superpowers:test-driven-development 1, superpowers:verification-before-completion 1 |

### report

Coder final reports: n 194, mean 3482 B, median 3774.5 B, `## Gate Results` share 0.2497; short form 0, legacy form 138.

### prod

Coder runs with at least one contract prod: 108 of 194.


## Process vs progress: G--git-Organizer, start to 2026-10-05

### subagents (0 transcripts)

| Bucket | Events | Load (tokens) | Output tokens | Wall (s) |
|---|---|---|---|---|

Process share, process / (process + progress): load None, output None, wall None. Model time (span minus tool time): 0 s.
Unclassified, top tools: none

### main (0 transcripts)

| Bucket | Events | Load (tokens) | Output tokens | Wall (s) |
|---|---|---|---|---|

Process share, process / (process + progress): load None, output None, wall None. Model time (span minus tool time): 0 s.
Unclassified, top tools: none

### spawn

| Agent type | Runs | Mean prompt B | Mean Skill B | Runs with a Skill | TDD opened, by tier | Skills opened |
|---|---|---|---|---|---|---|

### report

Coder final reports: n 0, mean 0 B, median 0 B, `## Gate Results` share 0.0; short form 0, legacy form 0.

### prod

Coder runs with at least one contract prod: 0 of 0.


## Process vs progress: G--git-WebSiteVerifier, start to 2026-10-05

### subagents (72 transcripts)

| Bucket | Events | Load (tokens) | Output tokens | Wall (s) |
|---|---|---|---|---|
| process:review | 316 | 4813515 | 295071 | 5995 |
| process:rules | 134 | 10962879 | 133 | 177 |
| process:prod | 282 | 2292954 | 48614 | 8014 |
| process:report | 103 | 5734 | 16243 | 148 |
| process:gate | 248 | 4373927 | 2533 | 22597 |
| process:wait | 2 | 14019 | 6 | 0 |
| progress:commit | 64 | 107946 | 1152 | 0 |
| progress:edit | 429 | 797298 | 3553 | 681 |
| progress:deliver | 6 | 10766 | 69 | 89 |
| neutral:orient | 1286 | 32586430 | 258721 | 19445 |
| neutral:spawn | 42 | 380836 | 0 | 0 |

Process share, process / (process + progress): load 0.9608, output 0.987, wall 0.9796. Model time (span minus tool time): 21681 s.
Unclassified, top tools: none

### main (1 transcripts)

| Bucket | Events | Load (tokens) | Output tokens | Wall (s) |
|---|---|---|---|---|
| process:rules | 10 | 13250608 | 3138 | 30 |
| process:gate | 6 | 334622 | 3425 | 2371 |
| process:wait | 2 | 22647 | 325 | 10 |
| progress:commit | 13 | 88047 | 4270 | 0 |
| progress:edit | 40 | 685479 | 39091 | 126 |
| progress:deliver | 66 | 1393549 | 31883 | 2735 |
| neutral:orient | 398 | 13746007 | 173612 | 6762 |
| neutral:spawn | 72 | 5739900 | 94707 | 798 |
| unclassified | 174 | 32227694 | 70299 | 1893 |

Process share, process / (process + progress): load 0.8626, output 0.0839, wall 0.4573. Model time (span minus tool time): 700341 s.
Unclassified, top tools: mcp__template-sync-tools__template_apply_file 28, SendMessage 26, mcp__open-brain__thoughts_capture 13, mcp__github-tools__github_release_upload_asset 8, mcp__github-tools__github_workflow_run_wait 7, mcp__template-sync-tools__template_migrate_manifest 7, mcp__MCP_DOCKER__pull_request_read 6, mcp__open-brain__task_create 6, mcp__open-brain__task_update 6, ListAgents 5

### spawn

| Agent type | Runs | Mean prompt B | Mean Skill B | Runs with a Skill | TDD opened, by tier | Skills opened |
|---|---|---|---|---|---|---|
| Explore | 1 | 2260 | 0 | 0 | unknown 0/1 | none |
| architect | 2 | 3757 | 9142 | 2 | T3 0/1, unknown 0/1 | superpowers:writing-plans 2 |
| code-reviewer | 4 | 1883 | 0 | 0 | unknown 0/4 | none |
| coder | 1 | 2601 | 3572 | 1 | T1 0/1 | superpowers:verification-before-completion 1 |
| general-purpose | 32 | 2975 | 0 | 0 | unknown 0/32 | none |
| ops | 5 | 1716 | 0 | 0 | unknown 0/5 | none |
| python-coder | 27 | 3841 | 23322 | 27 | unknown 27/27 | superpowers:receiving-code-review 27, superpowers:test-driven-development 27, superpowers:verification-before-completion 27, karpathy-guidelines 22 |

### report

Coder final reports: n 28, mean 4262 B, median 4367.5 B, `## Gate Results` share 0.3619; short form 0, legacy form 28.

### prod

Coder runs with at least one contract prod: 27 of 28.


## Process vs progress: G--git-Yutraffic-Challenge, start to 2026-10-05

### subagents (38 transcripts)

| Bucket | Events | Load (tokens) | Output tokens | Wall (s) |
|---|---|---|---|---|
| process:review | 26 | 85023 | 999 | 179 |
| process:rules | 29 | 2667734 | 18 | 37 |
| process:prod | 17 | 6368 | 6348 | 2993 |
| process:report | 35 | 152 | 3918 | 16 |
| process:gate | 58 | 3073137 | 3645 | 15362 |
| process:wait | 3 | 480 | 7 | 9 |
| progress:commit | 6 | 44016 | 1203 | 6 |
| progress:edit | 116 | 468870 | 8252 | 135 |
| progress:deliver | 15 | 12338 | 1763 | 155 |
| neutral:orient | 808 | 17444476 | 42225 | 6536 |
| neutral:spawn | 24 | 441024 | 0 | 0 |
| unclassified | 294 | 2496850 | 9744 | 491 |

Process share, process / (process + progress): load 0.9174, output 0.5711, wall 0.9844. Model time (span minus tool time): 12296 s.
Unclassified, top tools: mcp__github-tools__github_check_runs_for_sha 50, SendMessage 42, mcp__git-tools__git_status 23, mcp__git-tools__git_commit 19, mcp__git-tools__git_push 19, mcp__git-tools__git_add 18, mcp__MCP_DOCKER__pull_request_read 15, mcp__git-tools__git_log 14, mcp__github-tools__gh_workflow_list 14, mcp__yutraffic-game-test__click_light 8

### main (1 transcripts)

| Bucket | Events | Load (tokens) | Output tokens | Wall (s) |
|---|---|---|---|---|
| process:rules | 6 | 44948735 | 1752 | 2 |
| process:gate | 62 | 7734613 | 64375 | 13291 |
| process:wait | 23 | 3466346 | 8893 | 5 |
| progress:commit | 35 | 2728786 | 17256 | 11 |
| progress:edit | 447 | 29256723 | 696992 | 742 |
| progress:deliver | 137 | 12897695 | 92400 | 1455 |
| neutral:orient | 1348 | 204974318 | 836466 | 38036 |
| neutral:spawn | 39 | 11439430 | 74140 | 35 |
| unclassified | 900 | 854867209 | 696914 | 43337 |

Process share, process / (process + progress): load 0.5558, output 0.0851, wall 0.8576. Model time (span minus tool time): 3231942 s.
Unclassified, top tools: mcp__template-sync-tools__template_apply_file 227, SendMessage 168, mcp__plugin_context-mode_context-mode__ctx_execute 146, mcp__template-sync-tools__template_compute_status 46, mcp__open-brain__thoughts_capture 35, mcp__template-sync-tools__template_load_manifest 32, mcp__github-tools__github_check_runs_for_sha 31, mcp__template-sync-tools__template_finalize_sync 25, mcp__template-sync-tools__template_verify 23, mcp__template-sync-tools__template_get_diff 19

### spawn

| Agent type | Runs | Mean prompt B | Mean Skill B | Runs with a Skill | TDD opened, by tier | Skills opened |
|---|---|---|---|---|---|---|
| Explore | 5 | 4965 | 0 | 0 | unknown 0/5 | none |
| architect | 1 | 2539 | 0 | 0 | unknown 0/1 | none |
| cast-remover | 1 | 6551 | 0 | 0 | unknown 0/1 | none |
| claude-code-guide | 1 | 4468 | 0 | 0 | unknown 0/1 | none |
| closeout-coder | 1 | 6837 | 0 | 0 | unknown 0/1 | none |
| closeout-fixer | 1 | 8790 | 0 | 0 | unknown 0/1 | none |
| closeout-lander | 1 | 6663 | 0 | 0 | unknown 0/1 | none |
| closeout-reviewer | 1 | 6781 | 0 | 0 | unknown 0/1 | none |
| code-reviewer | 1 | 6058 | 0 | 0 | unknown 0/1 | none |
| coder | 4 | 6709 | 22723 | 4 | unknown 4/4 | superpowers:receiving-code-review 4, superpowers:test-driven-development 4, superpowers:verification-before-completion 4, karpathy-guidelines 3 |
| corridor-gate | 1 | 4667 | 0 | 0 | unknown 0/1 | none |
| corridor-mockup | 1 | 6907 | 0 | 0 | unknown 0/1 | none |
| crossref-gate | 1 | 4140 | 0 | 0 | unknown 0/1 | none |
| fix-shipper | 1 | 5703 | 0 | 0 | unknown 0/1 | none |
| gate-runner | 1 | 4635 | 0 | 0 | unknown 0/1 | none |
| ops | 8 | 5114 | 0 | 0 | unknown 0/8 | none |
| plan-challenger | 1 | 7242 | 0 | 0 | T3 0/1 | none |
| playtest-assets | 1 | 5691 | 0 | 0 | unknown 0/1 | none |
| playtest-gate | 1 | 4604 | 0 | 0 | unknown 0/1 | none |
| playtest-scribe | 1 | 9598 | 0 | 0 | unknown 0/1 | none |
| playtester | 1 | 6734 | 0 | 0 | unknown 0/1 | none |
| runner-revive | 1 | 6030 | 0 | 0 | unknown 0/1 | none |
| state-doc-reviewer | 1 | 5899 | 0 | 0 | unknown 0/1 | none |
| sweep-coder | 1 | 6896 | 0 | 0 | T2 0/1 | none |

### report

Coder final reports: n 6, mean 2366 B, median 2628.5 B, `## Gate Results` share 0.2057; short form 0, legacy form 3.

### prod

Coder runs with at least one contract prod: 4 of 6.


## Process vs progress: G--git-open-brain, start to 2026-10-05

### subagents (50 transcripts)

| Bucket | Events | Load (tokens) | Output tokens | Wall (s) |
|---|---|---|---|---|
| process:review | 47 | 168105 | 4130 | 36 |
| process:rules | 70 | 4955278 | 1395 | 91 |
| process:prod | 5 | 599 | 360 | 64 |
| process:report | 54 | 122 | 18683 | 19 |
| process:gate | 127 | 758497 | 26854 | 4778 |
| process:wait | 8 | 10392 | 129 | 0 |
| progress:commit | 17 | 24790 | 4978 | 102 |
| progress:edit | 115 | 251579 | 24607 | 128 |
| progress:deliver | 47 | 37266 | 9177 | 802 |
| neutral:orient | 621 | 4056305 | 103008 | 6475 |
| neutral:spawn | 27 | 354271 | 0 | 0 |
| unclassified | 43 | 83409 | 2953 | 67 |

Process share, process / (process + progress): load 0.9495, output 0.5708, wall 0.8285. Model time (span minus tool time): 6574 s.
Unclassified, top tools: mcp__github-tools__github_check_runs_for_sha 37, mcp__github-tools__gh_workflow_list 5, mcp__github-tools__gh_repo_from_origin 1

### main (1 transcripts)

| Bucket | Events | Load (tokens) | Output tokens | Wall (s) |
|---|---|---|---|---|
| process:rules | 4 | 36022325 | 3310 | 0 |
| process:gate | 101 | 27771649 | 124212 | 4528 |
| progress:commit | 27 | 2317844 | 11230 | 101 |
| progress:edit | 208 | 10875418 | 349807 | 312 |
| progress:deliver | 76 | 5428897 | 40413 | 990 |
| neutral:orient | 1075 | 174206483 | 674262 | 23245 |
| neutral:spawn | 51 | 15145091 | 85382 | 51 |
| unclassified | 521 | 348897140 | 523246 | 2465 |

Process share, process / (process + progress): load 0.774, output 0.2411, wall 0.7636. Model time (span minus tool time): 2943991 s.
Unclassified, top tools: SendMessage 141, mcp__template-sync-tools__template_apply_file 137, mcp__open-brain__thoughts_capture 83, mcp__template-sync-tools__template_load_manifest 36, mcp__template-sync-tools__template_compute_status 32, mcp__template-sync-tools__template_verify 19, mcp__template-sync-tools__template_finalize_sync 17, mcp__MCP_DOCKER__pull_request_read 15, mcp__template-sync-tools__template_get_diff 12, mcp__open-brain__thoughts_supersede 7

### spawn

| Agent type | Runs | Mean prompt B | Mean Skill B | Runs with a Skill | TDD opened, by tier | Skills opened |
|---|---|---|---|---|---|---|
| claude-code-guide | 1 | 4004 | 0 | 0 | unknown 0/1 | none |
| code-reviewer | 1 | 5164 | 4905 | 1 | unknown 0/1 | karpathy-guidelines 1 |
| coder | 13 | 7807 | 19444 | 13 | T1 1/1, T2 3/3, T3 4/4, unknown 3/5 | superpowers:verification-before-completion 13, superpowers:receiving-code-review 11, superpowers:test-driven-development 11, karpathy-guidelines 8 |
| ops | 35 | 4367 | 408 | 4 | unknown 0/35 | superpowers:verification-before-completion 4 |

### report

Coder final reports: n 13, mean 3736 B, median 3642 B, `## Gate Results` share 0.2152; short form 0, legacy form 13.

### prod

Coder runs with at least one contract prod: 2 of 13.


## Process vs progress: G--git-panoscribe, start to 2026-10-05

### subagents (98 transcripts)

| Bucket | Events | Load (tokens) | Output tokens | Wall (s) |
|---|---|---|---|---|
| process:review | 44 | 369105 | 42473 | 342 |
| process:rules | 63 | 3895998 | 445 | 87 |
| process:prod | 77 | 218939 | 2943 | 579 |
| process:report | 86 | 91 | 9034 | 19 |
| process:gate | 230 | 2264844 | 23449 | 32327 |
| process:wait | 28 | 29943 | 383 | 10 |
| progress:commit | 24 | 29947 | 12580 | 9 |
| progress:edit | 337 | 977202 | 26141 | 280 |
| progress:deliver | 67 | 48261 | 2185 | 324 |
| neutral:orient | 1618 | 38543697 | 164174 | 22293 |
| neutral:spawn | 53 | 1675250 | 0 | 0 |
| unclassified | 614 | 2157704 | 17491 | 1798 |

Process share, process / (process + progress): load 0.8653, output 0.6581, wall 0.9819. Model time (span minus tool time): 24477 s.
Unclassified, top tools: mcp__github-tools__github_check_runs_for_sha 159, mcp__git-tools__git_push 60, SendMessage 52, mcp__git-tools__git_status 50, mcp__git-tools__git_checkout 42, mcp__git-tools__git_add 25, mcp__git-tools__git_commit 24, mcp__github-tools__gh_workflow_list 24, mcp__git-tools__git_diff 23, mcp__git-tools__git_branch_delete 22

### main (1 transcripts)

| Bucket | Events | Load (tokens) | Output tokens | Wall (s) |
|---|---|---|---|---|
| process:rules | 8 | 47733525 | 7212 | 2 |
| process:gate | 86 | 23924268 | 90596 | 4302 |
| process:wait | 4 | 215407 | 795 | 0 |
| progress:commit | 37 | 1617315 | 15987 | 0 |
| progress:edit | 272 | 15451887 | 481140 | 537 |
| progress:deliver | 101 | 7641204 | 69513 | 2148 |
| neutral:orient | 1280 | 167480865 | 817759 | 28646 |
| neutral:spawn | 98 | 30754366 | 182226 | 123 |
| unclassified | 1086 | 735474844 | 823184 | 8928 |

Process share, process / (process + progress): load 0.7442, output 0.1482, wall 0.6159. Model time (span minus tool time): 3238426 s.
Unclassified, top tools: mcp__template-sync-tools__template_apply_file 196, SendMessage 189, mcp__open-brain__thoughts_capture 113, mcp__github-tools__github_check_runs_for_sha 94, mcp__github-tools__gh_workflow_list 77, mcp__github-tools__github_workflow_run_wait 67, mcp__template-sync-tools__template_compute_status 43, mcp__template-sync-tools__template_load_manifest 34, mcp__template-sync-tools__template_get_diff 25, mcp__template-sync-tools__template_finalize_sync 24

### spawn

| Agent type | Runs | Mean prompt B | Mean Skill B | Runs with a Skill | TDD opened, by tier | Skills opened |
|---|---|---|---|---|---|---|
| Explore | 2 | 4983 | 0 | 0 | unknown 0/2 | none |
| architect | 1 | 9065 | 22493 | 1 | unknown 0/1 | superpowers:brainstorming 1, superpowers:writing-plans 1 |
| bootstrap-fix | 1 | 5339 | 0 | 0 | T1 0/1 | none |
| challenge-design | 1 | 6172 | 0 | 0 | T4 0/1 | none |
| challenge-measure | 1 | 5948 | 0 | 0 | unknown 0/1 | none |
| changelog-fix | 1 | 6073 | 0 | 0 | T1 0/1 | none |
| code-reviewer | 1 | 6874 | 0 | 0 | unknown 0/1 | none |
| coder | 2 | 6693 | 9663 | 1 | T1 1/2 | superpowers:receiving-code-review 1, superpowers:test-driven-development 1, superpowers:verification-before-completion 1 |
| docs-stale-cache | 1 | 5383 | 0 | 0 | T1 0/1 | none |
| final-070 | 1 | 6066 | 0 | 0 | unknown 0/1 | none |
| final-080 | 1 | 6190 | 0 | 0 | unknown 0/1 | none |
| final-sweep | 1 | 5374 | 0 | 0 | unknown 0/1 | none |
| final-verify | 1 | 5704 | 0 | 0 | unknown 0/1 | none |
| fix-create-release | 1 | 6682 | 0 | 0 | T2 0/1 | none |
| fix-publish-gate | 1 | 6267 | 0 | 0 | T2 0/1 | none |
| gate-bootstrap | 1 | 3888 | 0 | 0 | unknown 0/1 | none |
| gate-clock-diag | 1 | 5677 | 0 | 0 | unknown 0/1 | none |
| gate-diagnose | 1 | 4707 | 0 | 0 | unknown 0/1 | none |
| gate-final | 1 | 4262 | 0 | 0 | unknown 0/1 | none |
| gate-main | 1 | 4360 | 0 | 0 | unknown 0/1 | none |
| gate-main2 | 1 | 4356 | 0 | 0 | unknown 0/1 | none |
| gate-refresh | 1 | 3924 | 0 | 0 | unknown 0/1 | none |
| general-purpose | 4 | 7625 | 4873 | 2 | T1 0/1, unknown 0/3 | karpathy-guidelines 2, superpowers:receiving-code-review 1, superpowers:verification-before-completion 1 |
| metadata-comment | 1 | 5495 | 0 | 0 | T1 0/1 | none |
| ocr-data | 1 | 5207 | 0 | 0 | unknown 0/1 | none |
| ops | 38 | 5332 | 1034 | 11 | unknown 0/38 | superpowers:verification-before-completion 11 |
| phase4-recon | 1 | 6777 | 0 | 0 | unknown 0/1 | none |
| publish-diag | 1 | 4902 | 0 | 0 | unknown 0/1 | none |
| pypi-verify | 1 | 5377 | 0 | 0 | unknown 0/1 | none |
| python-coder | 10 | 7804 | 0 | 0 | T2 0/1, T3 0/9 | none |
| recon-e2e-ocr | 1 | 5989 | 0 | 0 | unknown 0/1 | none |
| release-040 | 1 | 6714 | 0 | 0 | T2 0/1 | none |
| release-050 | 1 | 7342 | 0 | 0 | T2 0/1 | none |
| release-060 | 1 | 7236 | 0 | 0 | T2 0/1 | none |
| release-070 | 1 | 7461 | 0 | 0 | T2 0/1 | none |
| release-080 | 1 | 8102 | 0 | 0 | T2 0/1 | none |
| release-diag | 1 | 6267 | 0 | 0 | unknown 0/1 | none |
| rename-audit | 1 | 5168 | 0 | 0 | unknown 0/1 | none |
| sampler-recon | 1 | 5911 | 0 | 0 | unknown 0/1 | none |
| skip-existing | 1 | 5314 | 0 | 0 | T1 0/1 | none |
| testpypi-install | 1 | 5656 | 0 | 0 | unknown 0/1 | none |
| twine-debug | 1 | 5791 | 0 | 0 | unknown 0/1 | none |
| typo-recon | 1 | 6304 | 0 | 0 | unknown 0/1 | none |
| v1-recon | 1 | 5587 | 0 | 0 | unknown 0/1 | none |
| verify-060 | 1 | 5185 | 0 | 0 | unknown 0/1 | none |
| verify2 | 1 | 4824 | 0 | 0 | unknown 0/1 | none |
| verify3 | 1 | 5171 | 0 | 0 | unknown 0/1 | none |

### report

Coder final reports: n 12, mean 4241 B, median 4428.5 B, `## Gate Results` share 0.302; short form 0, legacy form 10.

### prod

Coder runs with at least one contract prod: 12 of 12.


## Process vs progress: G--git-penumbra, start to 2026-10-05

### subagents (271 transcripts)

| Bucket | Events | Load (tokens) | Output tokens | Wall (s) |
|---|---|---|---|---|
| process:review | 329 | 5650150 | 189700 | 4674 |
| process:test | 83 | 1404344 | 29342 | 1674 |
| process:rules | 316 | 31833668 | 6679 | 380 |
| process:prod | 661 | 7423742 | 183211 | 9067 |
| process:report | 236 | 61 | 63983 | 7 |
| process:gate | 590 | 7581667 | 119725 | 18448 |
| process:wait | 11 | 45172 | 531 | 17 |
| progress:commit | 70 | 221425 | 26771 | 0 |
| progress:edit | 1696 | 3221586 | 1303817 | 2665 |
| progress:deliver | 274 | 342287 | 44346 | 2391 |
| neutral:orient | 6459 | 198475407 | 2074458 | 116060 |
| neutral:spawn | 124 | 5236985 | 0 | 0 |
| unclassified | 1330 | 16834404 | 293698 | 5910 |

Process share, process / (process + progress): load 0.9344, output 0.3014, wall 0.8714. Model time (span minus tool time): 268210 s.
Unclassified, top tools: mcp__plugin_context-mode_context-mode__ctx_execute 389, mcp__plugin_context-mode_context-mode__ctx_fetch_and_index 125, mcp__git-tools__git_status 107, SendMessage 99, mcp__git-tools__git_diff 59, mcp__plugin_context-mode_context-mode__ctx_search 53, mcp__git-tools__git_diff_summary 51, mcp__searxng__search 45, mcp__git-tools__git_branch_list 43, mcp__git-tools__git_add 40

### main (1 transcripts)

| Bucket | Events | Load (tokens) | Output tokens | Wall (s) |
|---|---|---|---|---|
| process:rules | 8 | 61478172 | 5887 | 9 |
| process:gate | 114 | 20272171 | 80990 | 7166 |
| process:wait | 6 | 1123128 | 2826 | 5 |
| progress:commit | 84 | 7904455 | 55510 | 17 |
| progress:edit | 458 | 35114106 | 657058 | 954 |
| progress:deliver | 199 | 23541563 | 129481 | 2439 |
| neutral:orient | 2584 | 754951245 | 1433887 | 34676 |
| neutral:spawn | 263 | 104287021 | 466252 | 319 |
| unclassified | 999 | 1007161313 | 745280 | 6510 |

Process share, process / (process + progress): load 0.5546, output 0.0963, wall 0.678. Model time (span minus tool time): 3580594 s.
Unclassified, top tools: SendMessage 267, mcp__template-sync-tools__template_apply_file 207, mcp__open-brain__thoughts_capture 81, mcp__plugin_context-mode_context-mode__ctx_execute 48, mcp__template-sync-tools__template_compute_status 42, mcp__template-sync-tools__template_load_manifest 35, mcp__git-tools__git_status 29, mcp__template-sync-tools__template_get_diff 25, mcp__git-tools__git_add 24, mcp__git-tools__git_commit 24

### spawn

| Agent type | Runs | Mean prompt B | Mean Skill B | Runs with a Skill | TDD opened, by tier | Skills opened |
|---|---|---|---|---|---|---|
| Explore | 7 | 4111 | 0 | 0 | unknown 0/7 | none |
| Plan | 1 | 6536 | 0 | 0 | unknown 0/1 | none |
| architect | 5 | 5878 | 12075 | 3 | unknown 0/5 | superpowers:brainstorming 3, superpowers:writing-plans 2 |
| audit-method | 1 | 5255 | 0 | 0 | unknown 0/1 | none |
| audit-p0 | 1 | 4314 | 0 | 0 | unknown 0/1 | none |
| audit-p6 | 1 | 4980 | 0 | 0 | unknown 0/1 | none |
| audit-priorart | 1 | 5496 | 0 | 0 | unknown 0/1 | none |
| audit-x5 | 1 | 5352 | 0 | 0 | unknown 0/1 | none |
| b3-a4 | 1 | 4952 | 0 | 0 | unknown 0/1 | none |
| b3-bpip | 1 | 4746 | 0 | 0 | unknown 0/1 | none |
| b3-exp | 1 | 5301 | 0 | 0 | unknown 0/1 | none |
| b3-lit | 1 | 5399 | 0 | 0 | unknown 0/1 | none |
| b3-sprt | 1 | 5826 | 0 | 0 | unknown 0/1 | none |
| caveman:cavecrew-investigator | 1 | 3447 | 0 | 0 | unknown 0/1 | none |
| caveman:cavecrew-reviewer | 1 | 4524 | 0 | 0 | unknown 0/1 | none |
| cii-discharge | 1 | 6472 | 0 | 0 | unknown 0/1 | none |
| code-reviewer | 4 | 5438 | 0 | 0 | unknown 0/4 | none |
| coder | 2 | 8733 | 14365 | 2 | unknown 1/2 | karpathy-guidelines 2, superpowers:verification-before-completion 2, superpowers:receiving-code-review 1, superpowers:test-driven-development 1 |
| consistency-challenge | 1 | 5881 | 0 | 0 | unknown 0/1 | none |
| coverage-retry | 1 | 5878 | 0 | 0 | unknown 0/1 | none |
| coverage-sim | 1 | 6231 | 0 | 0 | unknown 0/1 | none |
| cpp-coder | 8 | 6909 | 15583 | 7 | unknown 4/8 | superpowers:receiving-code-review 7, karpathy-guidelines 5, superpowers:test-driven-development 4, superpowers:verification-before-completion 4, superpowers:using-git-worktrees 1 |
| f77-challenge | 1 | 5919 | 0 | 0 | unknown 0/1 | none |
| forum-fishtest | 1 | 5908 | 0 | 0 | unknown 0/1 | none |
| forum-talkchess | 1 | 6203 | 0 | 0 | unknown 0/1 | none |
| general-purpose | 9 | 5803 | 0 | 0 | unknown 0/9 | none |
| halfopen-priorart | 1 | 8662 | 0 | 0 | unknown 0/1 | none |
| merge-71 | 1 | 4446 | 0 | 0 | unknown 0/1 | none |
| node-odds | 1 | 5988 | 0 | 0 | unknown 0/1 | none |
| ops | 71 | 5030 | 723 | 14 | unknown 0/71 | superpowers:verification-before-completion 13, karpathy-guidelines 1 |
| p0-null-cli | 1 | 5317 | 0 | 0 | unknown 0/1 | none |
| p0-recheck | 1 | 4416 | 0 | 0 | unknown 0/1 | none |
| p6-close | 1 | 5575 | 0 | 0 | unknown 0/1 | none |
| pkg-writeups | 1 | 9496 | 0 | 0 | unknown 0/1 | none |
| propagate-78 | 1 | 6412 | 0 | 0 | unknown 0/1 | none |
| python-coder | 41 | 7632 | 18321 | 38 | unknown 32/41 | superpowers:verification-before-completion 37, superpowers:test-driven-development 32, superpowers:receiving-code-review 29, karpathy-guidelines 18, superpowers:systematic-debugging 5, superpowers:brainstorming 1 |
| r3-exp | 1 | 5006 | 0 | 0 | unknown 0/1 | none |
| r3-lit | 1 | 4768 | 0 | 0 | unknown 0/1 | none |
| r3-sprt | 1 | 4852 | 0 | 0 | unknown 0/1 | none |
| refute-batch2-rest | 1 | 4959 | 0 | 0 | unknown 0/1 | none |
| refute-f17-f28 | 1 | 5264 | 0 | 0 | unknown 0/1 | none |
| refute-f47 | 1 | 5342 | 0 | 0 | unknown 0/1 | none |
| refute-f57-f62 | 1 | 4900 | 0 | 0 | unknown 0/1 | none |
| rho-design-review | 1 | 6556 | 0 | 0 | unknown 0/1 | none |
| rho-gate | 1 | 5552 | 0 | 0 | unknown 0/1 | none |
| rho-priorart | 1 | 6783 | 0 | 0 | unknown 0/1 | none |
| rho-scope | 1 | 6517 | 0 | 0 | unknown 0/1 | none |
| science-reviewer | 32 | 6177 | 669 | 6 | unknown 0/32 | superpowers:verification-before-completion 6 |
| ship-73 | 1 | 5501 | 0 | 0 | unknown 0/1 | none |
| ship-74 | 1 | 5221 | 0 | 0 | unknown 0/1 | none |
| ship-75 | 1 | 5193 | 0 | 0 | unknown 0/1 | none |
| ship-76 | 1 | 5599 | 0 | 0 | unknown 0/1 | none |
| ship-77 | 1 | 5902 | 0 | 0 | unknown 0/1 | none |
| ship-c44 | 1 | 4901 | 0 | 0 | unknown 0/1 | none |
| ship-cleanup | 1 | 6343 | 0 | 0 | unknown 0/1 | none |
| ship-f71 | 1 | 5127 | 0 | 0 | unknown 0/1 | none |
| ship-f72 | 1 | 5241 | 0 | 0 | unknown 0/1 | none |
| ship-orphan | 1 | 5149 | 0 | 0 | unknown 0/1 | none |
| status-audit | 1 | 5664 | 0 | 0 | unknown 0/1 | none |
| status-fix | 1 | 5787 | 0 | 0 | unknown 0/1 | none |
| sweep-a | 1 | 4590 | 0 | 0 | unknown 0/1 | none |
| sweep-b | 1 | 4686 | 0 | 0 | unknown 0/1 | none |
| sweep-c | 1 | 5069 | 0 | 0 | unknown 0/1 | none |
| tester | 2 | 5662 | 22167 | 2 | unknown 2/2 | superpowers:systematic-debugging 2, superpowers:test-driven-development 2, superpowers:verification-before-completion 2 |
| uho-book | 1 | 6269 | 0 | 0 | unknown 0/1 | none |
| writeup-factcheck | 1 | 5827 | 0 | 0 | unknown 0/1 | none |
| writeup-fix | 1 | 5822 | 0 | 0 | unknown 0/1 | none |
| x1-fix | 1 | 6145 | 0 | 0 | unknown 0/1 | none |
| x1-outdir | 1 | 5111 | 0 | 0 | unknown 0/1 | none |
| x10-rescope | 1 | 8727 | 0 | 0 | unknown 0/1 | none |
| x11-robust | 1 | 5866 | 0 | 0 | unknown 0/1 | none |
| x11-run | 1 | 6276 | 0 | 0 | unknown 0/1 | none |
| x11-verify | 1 | 5449 | 0 | 0 | unknown 0/1 | none |
| x12-build | 1 | 6204 | 0 | 0 | unknown 0/1 | none |
| x12-kc0 | 1 | 8597 | 0 | 0 | unknown 0/1 | none |
| x12-mid | 1 | 6025 | 0 | 0 | unknown 0/1 | none |
| x12-resume | 1 | 5719 | 0 | 0 | unknown 0/1 | none |
| x12-sf10 | 1 | 5468 | 0 | 0 | unknown 0/1 | none |
| x12-sf18-ext | 1 | 5523 | 0 | 0 | unknown 0/1 | none |
| x12a-derive | 1 | 6329 | 0 | 0 | unknown 0/1 | none |
| x2-priorart | 1 | 6616 | 0 | 0 | unknown 0/1 | none |
| x2-scope | 1 | 5851 | 0 | 0 | unknown 0/1 | none |
| x2-scope2 | 1 | 5994 | 0 | 0 | unknown 0/1 | none |
| x2c-accumfix | 1 | 6158 | 0 | 0 | unknown 0/1 | none |
| x2c-analysis | 1 | 6966 | 0 | 0 | unknown 0/1 | none |
| x2c-corpus | 1 | 6749 | 0 | 0 | unknown 0/1 | none |
| x2c-corpus-prep | 1 | 5928 | 0 | 0 | unknown 0/1 | none |
| x2c-debug | 1 | 6603 | 0 | 0 | unknown 0/1 | none |
| x2c-design-review | 1 | 6404 | 0 | 0 | unknown 0/1 | none |
| x2c-review2 | 1 | 6449 | 0 | 0 | unknown 0/1 | none |
| x2c-round1 | 1 | 5467 | 0 | 0 | unknown 0/1 | none |
| x2c-run | 1 | 6109 | 0 | 0 | unknown 0/1 | none |
| x2c-run2 | 1 | 6184 | 0 | 0 | unknown 0/1 | none |
| x2c-ship | 1 | 5241 | 0 | 0 | unknown 0/1 | none |
| x2c-smoke | 1 | 5859 | 0 | 0 | unknown 0/1 | none |
| x2c-stageb | 1 | 6344 | 0 | 0 | unknown 0/1 | none |
| x6b-cost | 1 | 5767 | 0 | 0 | unknown 0/1 | none |
| x6b-fixups | 1 | 5341 | 0 | 0 | unknown 0/1 | none |
| x6b-gate | 1 | 5656 | 0 | 0 | unknown 0/1 | none |
| x6b-priorart | 1 | 6658 | 0 | 0 | unknown 0/1 | none |

### report

Coder final reports: n 51, mean 3224 B, median 3416 B, `## Gate Results` share 0.189; short form 0, legacy form 41.

### prod

Coder runs with at least one contract prod: 23 of 51.


## Process vs progress: G--git-pixel-agents, start to 2026-10-05

### subagents (0 transcripts)

| Bucket | Events | Load (tokens) | Output tokens | Wall (s) |
|---|---|---|---|---|

Process share, process / (process + progress): load None, output None, wall None. Model time (span minus tool time): 0 s.
Unclassified, top tools: none

### main (0 transcripts)

| Bucket | Events | Load (tokens) | Output tokens | Wall (s) |
|---|---|---|---|---|

Process share, process / (process + progress): load None, output None, wall None. Model time (span minus tool time): 0 s.
Unclassified, top tools: none

### spawn

| Agent type | Runs | Mean prompt B | Mean Skill B | Runs with a Skill | TDD opened, by tier | Skills opened |
|---|---|---|---|---|---|---|

### report

Coder final reports: n 0, mean 0 B, median 0 B, `## Gate Results` share 0.0; short form 0, legacy form 0.

### prod

Coder runs with at least one contract prod: 0 of 0.


