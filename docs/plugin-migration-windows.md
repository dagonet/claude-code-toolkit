# Moving a Windows PC from the v4.x user level to the cct plugin

On Linux `scripts/install-user-level-linux.sh` does steps 1-3 in this order. On the PC they are done by hand, in this order: the plugin is installed **before** anything is removed, so at every step exactly one copy of each hook acts (spec §4, steps 2-3). If step 1 fails, stop: the v4.x copies keep the machine protected.

1. **Install the plugin.** In a Claude Code session:
   ```
   /plugin marketplace add dagonet/claude-code-toolkit#v5.0.0
   /plugin install cct@dagonet
   ```
   Check that `claude plugin list` shows `cct@dagonet` at version `5.0.0`. Until step 2 the old user-level copies are still registered; the plugin steps aside for them, so nothing fires twice.

2. **Back up `~/.claude/settings.json`, then remove its six toolkit hook entries.** Copy the file to `settings.json.bak-<date>`. Then delete each hook entry whose `args` name `<home>/.claude/hooks/<name>.sh`, for these six names, and any matcher group left empty:
   - `no-push-main.sh` (`PreToolUse`, matcher `Bash|PowerShell`)
   - `deny-secret-reads.sh` (`PreToolUse`, matcher `Read|Bash`)
   - `deny-hang-shapes.sh` (`PreToolUse`, matcher `Bash`)
   - `model-floor.sh` (`PreToolUse`, matcher `Agent`)
   - `bash-output-guard.sh` (`PostToolUse`, matcher `Bash|PowerShell`)
   - `verify-hooks.sh` (`SessionStart`)

   Keep the `UserPromptSubmit` time hook and every hook you added yourself. Set `"outputStyle": "cct:pm-report"` (a plugin style loads only under the plugin prefix).

3. **Move every path in `scripts/lib/v4-user-leftovers.txt` to a dated backup folder.** Each line is relative to `~/.claude/`: six agents, nine skill directories, the `pm-report` output style and every file under `hooks/`. Move them to a folder outside `agents/`, `skills/`, `output-styles/` and `hooks/` (for example `~/.claude/v4-leftovers.bak-<date>/`, keeping the relative paths): a backup copy left inside `skills/` would still load as a second skill. Then delete the empty `~/.claude/hooks/lib/` and `~/.claude/hooks/`.

4. **Re-arm Jev where it is on.** In each checkout where Jev routing is on, run `/cct:jev off` and then `/cct:jev on`. Both remove the v4.x Jev registration from that checkout's `.claude/settings.local.json` (it runs `~/.claude/skills/jev/jev_route.py`, moved away in step 3); the switch then lives in `<git common dir>/jev/config.json`, which the plugin's Jev hooks read.

5. **Restart all sessions.** A running session keeps the hooks and agents it started with.

6. **Check.** From the toolkit checkout:
   ```
   bash scripts/verify-user-level-drift.sh v5.0.0
   ```
   It must report 0 drift: `CLAUDE.md` equal to the reference, `cct@dagonet` installed at `5.0.0`, and no path from the leftovers list present.

**Later releases (v5.0.x and up):** the marketplace is pinned to a tag, so `/plugin update` and `claude plugin marketplace update` never advance it, and adding the marketplace over the existing entry is refused. Move to the new tag with `claude plugin marketplace remove dagonet`, then `claude plugin marketplace add dagonet/claude-code-toolkit#<new tag>`, then `claude plugin install cct@dagonet`, then restart every session. (The remove uninstalls the plugin: until the install succeeds, synced projects refuse every tool.) Check the tag exists first: `git ls-remote --tags https://github.com/dagonet/claude-code-toolkit refs/tags/<new tag>`.

**Rollback:** move the backed-up paths back, restore `settings.json.bak-<date>`, and restart. Uninstalling the plugin alone is not a rollback once a project is synced to v5.0: its guard then refuses, by design.
