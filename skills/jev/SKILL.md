---
name: jev
description: Switch the optional Jev spawn router on or off for this clone, or show its status or report. Triggers on /cct:jev.
disable-model-invocation: true
argument-hint: on | off | status | report
---

# /cct:jev — optional Jev spawn routing (v4.4.0, Phase 1a)

Run exactly one command, using the word the user typed after `/cct:jev` (no word means `status`), and relay its output verbatim:

    python3 "${CLAUDE_SKILL_DIR}/jev_ctl.py" status

(`on`, `off` or `report` in place of `status`.) Never edit `.claude/settings.local.json` or `<git common dir>/jev/config.json` yourself: `jev_ctl.py` writes the config, and `on`/`off` also clear a v4 registration left in the settings file (`off` restores that file byte for byte when nobody edited it since the v4 `/jev on`).

## What it does

- **On** (per clone): writes `{"model": "jev-1.13.0", "threshold": 0.65, "route": true, "legs": false}` to `<git common dir>/jev/config.json`. Nothing else is written: the cct plugin registers the router (`hooks/jev-route.sh`, `PreToolUse` `Agent`) and the session notice (`hooks/jev-notice.sh`) itself, and both act only while that file says `"route": true`. Every checkout of the clone, worktrees included, is covered by the one switch. A v4 `/jev on` left an entry in this checkout's `.claude/settings.local.json`; `on` and `off` remove it (until then the plugin steps aside for it, so routing never runs twice).
- **Per spawn** that passes no `model`: TypeSafe's Jev picks a model in ~0.3 s. It applies only at confidence ≥ 0.65 (the `threshold` in the config; a one-week trial value), and may pick any model on haiku < sonnet < opus < fable, never below sonnet for `review`/`architect` types, whose effort is also never lowered below the agent file's (with no agent effort they keep the session's). A spawn with no model of its own always leaves with one: Jev's choice, or the project floor when Jev is unsure, slow (2 s), unreachable or keyless. Jev's effort is applied at the same threshold when it differs from the agent file's `effort:` (an agent file without one counts as different); an `effort` you pass on the spawn is never changed. A typed agent whose model stays the same gets the effort only, never a pinned model.
- **Off**: the switch goes off first, so `hooks/model-floor.sh` floors again at once. Then any v4 registration and notice in `.claude/settings.local.json` are removed. Events stay for `/cct:jev report`.

`/cct:jev report` stays per clone. For the cross-machine trial tally over every clone under a root, run `python3 <toolkit>/scripts/jev-tally.py [--since DATE] [ROOT...]` (default root `~/git`; the PC passes `G:/git`). It is read-only and prints counts only.

## While on: omit `model` (user ruling U-1, 2026-10-02)

"Jev decides, I don't." While Jev routing is on in this repo, do NOT pass `model` on Agent spawns. Jev picks one per launch. This is the exception to the user-level rule "every Agent spawn names its `model`". After `/cct:jev off`, name `model` again. A `model` you do pass is never changed, so passing one opts that spawn out of routing.

AGENT_TEAM.md's "Typed agents own their `model`; a type without one (general-purpose, built-ins) gets the project default via `hooks/model-floor.sh` unless you pass one" is overridden for spawns Jev routes, within the bounds above: Jev may move a typed agent to any model and set its effort.

## What leaves the machine

Only for a spawn Jev routes: the agent type, description and prompt, with secrets, emails, your username and home paths masked, trimmed to 4,000 characters. A spawn whose text still holds a secret-shaped token is not sent at all. The key (`TYPESAFE_API_KEY`, else `HKCU\Environment`) goes in a header only and is never printed or logged. `<git common dir>/jev/events/` holds decisions and confidences, never the prompt or the key.
