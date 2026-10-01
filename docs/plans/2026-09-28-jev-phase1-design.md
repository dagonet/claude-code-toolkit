# Jev Phase 1 — design (optional TypeSafe Jev decision layer)

**Status:** spec for review. Branch `feat/jev-phase1` (worktree `G:/git/.worktrees/claude-code-toolkit/jev-phase1`), cut from `main` b43b140. **User rule: all Jev implementation stays off mainline until the user says otherwise.**
**Evidence:** Phase 0 offline replay (branch `spike/jev-phase0`, `spikes/jev-phase0/README.md`): 68 recorded subagent runs, 136 calls to `jev-1.13.0` (~0.3 s each). Against an Opus reference judge: model choice 98.5 % within one step (72 % exact), effort 97.1 % within one step (54 % exact); report questions failed (claims_done 64.7 %). **User decision (2026-09-28): GO for model and effort choice only.**

## Goal

Let an opted-in project route each subagent spawn to the cheapest adequate model, decided by Jev in ~0.3 s, bounded so a wrong call costs little — and, in a second phase, measure whether Jev can tell which optional gate legs a change needs, without skipping anything yet.

## Decisions (user, 2026-09-26 … 09-28)

| # | Decision |
|---|---|
| D1 | Optional, **default off**, switched **per clone**; **zero footprint when off** (nothing registered, nothing loaded). |
| D2 | Toolkit-native: a user-level skill with its script bundled (no template, no `hooks/` file, no plugin, no python client library). |
| D3 | Data sent: allowlisted fields only, secrets/emails/username/home paths masked, head+tail trimmed; egress fails closed on any residual secret-shaped token. |
| D4 | Spawn routing **acts** when Jev's confidence ≥ threshold (default 0.8). |
| D5 | Bounds: at most **one step** from the agent file's default model; reviewer and architect roles **never below sonnet**; an explicit `model` passed by the orchestrator is **never** overridden. |
| D6 | Effort is **logged only** (the Agent tool has no effort parameter). |
| D7 | No session-model hint (user: every model switch re-sends the context; hooks cannot switch the main model anyway — only `/model`). |
| D8 | Leg-gating is **shadow only**: everything still runs; misses are counted; acting is a later, separate decision after zero misses over an agreed number of gates. |
| D9 | Order: **1a** spawn routing now → v4.3.0 performance release (adds per-leg results) → **1b** shadow leg-gating. |

## Phase 1a — spawn routing

### Switch

- User-level skill `user-level-reference/skills/jev/` → `~/.claude/skills/jev/`: `SKILL.md` (`disable-model-invocation: true` — zero always-loaded bytes, and the model can never enable egress itself) + `jev_route.py` + `redact.py` (the Phase 0 redactor, with its tests).
- `/jev on` (per clone):
  1. writes `<git common dir>/jev/config.json` = `{"model": "jev-1.13.0", "threshold": 0.8, "route": true, "legs": false}`;
  2. adds ONE `PreToolUse` entry with matcher `Agent` to the project's `.claude/settings.local.json`, command `f="$HOME/.claude/skills/jev/jev_route.py"; [ -f "$f" ] && python3 "$f"; exit 0` (a deleted skill is silent — the context-mode stale-hook lesson), `"timeout": 5`;
  3. adds `.claude/settings.local.json` to `.git/info/exclude` if absent.
- `/jev off` removes that entry (and only that entry). `/jev status` shows switch, config, key presence (never the key), last event. `/jev report` summarises the events.
- The skill states the one rule exception while on: `AGENT_TEAM.md`'s v4.3.0 line "Typed agents own their `model`; a type without one (general-purpose, built-ins) gets the project default via `hooks/model-floor.sh` unless you pass one" is overridden for spawns Jev routes, within D5's bounds (Jev may move a typed agent one step from its own model).

### Per spawn (`jev_route.py`, synchronous)

1. Read the PreToolUse payload. Not an `Agent` call, or `tool_input.model` set → log `explicit`/`skip`, exit 0, no output.
2. Resolve the default model exactly as v4.3.0's `hooks/model-floor.sh` does (updated 2026-10-02 to match the shipped hook). That means: by the agent file's frontmatter `name:` (recursive, project `.claude/agents/` then `~/.claude/agents/`, filename fallback); a non-empty model other than `inherit` is the default; `inherit`, no model, or an unresolved built-in (`general-purpose`, `Plan`, `Explore`, `claude`, empty type) → the v4.3.0 floor (`**Subagent default model**`, else `sonnet`); `statusline-setup`, `claude-code-guide`, `fork` and unknown types without a file → change nothing; `CLAUDE_CODE_SUBAGENT_MODEL` set to a real model → the floor steps aside where that variable applies (all spawns under `_FORCE=1`, else general-purpose and empty types only). While Jev routing is on, model-floor steps aside and this hook applies that floor itself, so the spawn never inherits the orchestrator's model even when Jev's call fails. Implementation reuses model-floor's resolution code rather than re-deriving it.
3. Build `state` = `agent_type`, `description`, `prompt`; redact (D3) then trim to 4,000 chars; residual finding → log `egress-refused`, change nothing.
4. Key from `TYPESAFE_API_KEY`, else `HKCU\Environment` (winreg); in a header only, never argv, never logged. No key → log `no-key`, change nothing.
5. `POST https://api.typesafe.ai/v1/systemone` with the Phase 0 `model` and `effort` questions (same instructions and criteria), `model` pinned to the config value; client timeout 2 s.
6. Apply only if ALL hold: `confidence ≥ threshold`; `|index(choice) − index(default)| ≤ 1` on `haiku < sonnet < opus < fable`; the role floor holds (`subagent_type` matching `review|architect` never below `sonnet`). Then print `{"hookSpecificOutput":{"hookEventName":"PreToolUse","updatedInput":{…the complete original tool_input…, "model": "<choice>"}}}` — with NO `permissionDecision`, exactly like v4.3.0's model-floor (ruling S-19: a router must never auto-approve a spawn). Otherwise print nothing. That form was verified live on 2026-10-01: a model-less `Plan` spawn ran on `claude-sonnet-5-5` with model-floor registered and on `claude-opus-5-5` only without it (updated 2026-10-02; previously this step emitted `permissionDecision: "allow"`). The implementation plan still verifies that a parallel exit-2 hook wins over the rewrite.
7. Any exception, timeout, HTTP error, unparseable response → no output, exit 0 (the agent file's default applies).
8. Log one event file `<git common dir>/jev/events/<utc-ts>-<pid>.json`: `{ts, subagent_type, default, choice, confidence, probabilities, applied, reason, effort_choice, effort_confidence, latency_s}` — never the state text, never the key.

### Report

`/jev report` reads the events: spawns seen, applied up / down / kept (by reason), confidence distribution, effort recommendation vs the agent file's `effort:`; and lists routed spawns whose agent later reported `BLOCKED`/`NEEDS_CONTEXT` (joined by time window from the SubagentStop retro ledger when present) — the first real-outcome signal.

## Phase 1b — shadow leg-gating (after v4.3.0)

Depends on v4.3.0: `**Gate extra**` separates the Test line from the extra legs, and `run-gate.sh` records each extra leg's exit code in the gate artifact (added to the v4.3.0 spec).

- Own toggle: `/jev on legs` (sets `"legs": true`); off by default even when routing is on — it sends a change summary (changed-file list + redacted, trimmed diff), i.e. code, off the machine.
- Trigger: the same `settings.local.json` mechanism, a `PreToolUse` `Bash` entry that only acts when the command runs `hooks/run-gate.sh`; for each declared extra leg it asks Jev `needed` (Noul) with the leg's command as context; logs predictions keyed by the tree. It NEVER changes what runs.
- After the gate: `/jev report` joins predictions with the per-leg exit codes in the gate artifact for the same tree: a **miss** = predicted skippable (`needed` < 0.5 with confidence ≥ threshold) but the leg failed; also reports minutes that would have been saved.
- Acting on leg predictions is out of scope for Phase 1; it needs a new spec and the user's decision after zero misses over an agreed number of gates.

## Testing

- `redact.py`: the 15 Phase 0 tests.
- `jev_route.py`: unit tests with a stubbed HTTP layer: explicit model untouched; missing/inherit default untouched; confidence below threshold untouched; two-step move refused; reviewer to haiku refused; valid one-step move emits `updatedInput` equal to the original input except `model`; timeout / 5xx / garbage response → no output, exit 0; no key → no output; residual secret → no call made.
- Skill: `/jev on` → `off` round trip leaves `settings.local.json` byte-identical to before (except a pre-existing absence); `status` never prints the key.
- Live: one routed spawn in a scratch project with the switch on, and the event file written.

## Non-goals

- No template, `hooks/` or `main` change in Phase 1; nothing ships to consumers.
- No report-quality questions (claims_done / shows_evidence).
- No session-model switching or hints.
- No acting on leg predictions.
