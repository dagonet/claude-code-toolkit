---
name: backlog-board
description: Create or update a project's live backlog board (a private web page with a colour-coded state per item). Use when a project with a backlog has no board yet (offer once), or after any backlog item changes state.
---

# Backlog board

A private page showing the project's backlog: one row per capability with a colour-coded state, a one-line note, a tally, and the latest headline. It pairs with the `pm-report` output style; where a board exists it is the source of truth for the backlog and the chat table mirrors it.

## States

| key | label |
|---|---|
| `done` | Done |
| `progress` | In progress |
| `testing` | Testing live |
| `rework` | Needs rework |
| `open` | Open |
| `waiting` | Waiting on you |
| `blocked` | Blocked |

## Create -- once per project, only after the user says yes

If the user declines, record `Backlog board: declined` in this project's auto-memory and do not offer again.

1. Load the `artifact-capabilities` skill (required before passing `capabilities`).
2. Copy `~/.claude/skills/backlog-board/board.html` into the session scratchpad and replace `__PROJECT_NAME__` with the project's plain name.
3. Publish it with the Artifact tool: `capabilities: {"db": {}}`, icon `list`, a one-sentence description. It is private by default.
4. Seed the data with ONE `ArtifactData` `batch` of `set` writes (new documents, so no `if_version`): collection `backlog`, doc ids `item-01`, `item-02`, ..., data `{order, title, state, note}`; and collection `meta`, doc `latest`, data `{headline, updated}`. Every row needs an `order` -- the page sorts by it, and a row without one is shown out of order or not at all. `updated` is an ISO 8601 string from `date -Iseconds`.
5. Record the page address in this project's auto-memory as a `project` memory ("Backlog board: <url>"). Never in a committed file.

## Update -- on every state change

1. `ArtifactData` `list` on collection `backlog` and `get` on collection `meta`, doc `latest`; each result carries the document's `version`.
2. ONE `batch`: an `update` per changed row plus `meta/latest` (new `headline`, `updated` from `date -Iseconds`), each entry pinned with `if_version` = the version just read. A new item is a `set` with the next `order` (a new document, not read, so no `if_version`).
3. To remove an item, `delete` it in the same batch, pinned with its `if_version`.
4. If the batch is refused because a document changed since the read, re-read and redo it -- never drop the pin.
5. Never republish the page for a data change: republishing does not touch the data and only churns versions.

## Rules

- Without a board, the backlog list lives in this project's auto-memory; the chat table is the only view.
- Notes are one plain sentence; the page renders them as text, so no HTML or markdown.
- Plain words only: no paths, commit ids, secrets or internal labels on the page.
- If the Artifact tools are not available in this session, report in chat only and say so once.
- Previews and thumbnails show an offline note (no live data there) -- expected, not a fault.
