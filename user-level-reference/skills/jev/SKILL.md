---
name: jev
description: Switch the optional Jev spawn router on or off for this clone, or show its status or report. Triggers on /jev.
disable-model-invocation: true
argument-hint: on | off | status | report
---

# /jev — optional Jev spawn routing (v4.4.0, Phase 1a)

Run exactly one command, using the word the user typed after `/jev` (no word means `status`), and relay its output verbatim:

    python3 ~/.claude/skills/jev/jev_ctl.py status

(`on`, `off` or `report` in place of `status`.) Never edit `.claude/settings.local.json` or `<git common dir>/jev/config.json` yourself: `jev_ctl.py` writes both, and `off` restores the settings file byte for byte when nobody edited it since `on`.

## What it does

- **On** (per clone): writes `{"model": "jev-1.13.0", "threshold": 0.8, "route": true, "legs": false}` to `<git common dir>/jev/config.json`, registers ONE `PreToolUse` entry (matcher `Agent`) and ONE `SessionStart` notice in this checkout's `.claude/settings.local.json`, and excludes that file from git. Another checkout (a worktree) of the same clone needs its own `/jev on`; until then `hooks/model-floor.sh` keeps flooring there.
- **Per spawn** that passes no `model`: TypeSafe's Jev picks a model in ~0.3 s. It applies only at confidence ≥ 0.8, at most one step from the default (the agent file's model, the project floor, or `CLAUDE_CODE_SUBAGENT_MODEL` where that applies), on haiku < sonnet < opus < fable, and never below sonnet for `review`/`architect` types. A spawn with no model of its own always leaves with one: Jev's choice, or the project floor when Jev is unsure, slow (2 s), unreachable or keyless. Effort is logged, never applied.
- **Off**: the switch goes off first, so `hooks/model-floor.sh` floors again at once. Then the registration and the notice are removed. Events stay for `/jev report`.

## While on: omit `model` (user ruling U-1, 2026-10-02)

"Jev decides, I don't." While Jev routing is on in this repo, do NOT pass `model` on Agent spawns. Jev picks one per launch. This is the exception to the user-level rule "every Agent spawn names its `model`". After `/jev off`, name `model` again. A `model` you do pass is never changed, so passing one opts that spawn out of routing.

AGENT_TEAM.md's "Typed agents own their `model`; a type without one (general-purpose, built-ins) gets the project default via `hooks/model-floor.sh` unless you pass one" is overridden for spawns Jev routes, within the bounds above: Jev may move a typed agent one step from its own model.

## What leaves the machine

Only for a spawn Jev routes: the agent type, description and prompt, with secrets, emails, your username and home paths masked, trimmed to 4,000 characters. A spawn whose text still holds a secret-shaped token is not sent at all. The key (`TYPESAFE_API_KEY`, else `HKCU\Environment`) goes in a header only and is never printed or logged. `<git common dir>/jev/events/` holds decisions and confidences, never the prompt or the key.
