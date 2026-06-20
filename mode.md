---
description: Switch the status line preset (mode) for THIS Claude session
---

The user wants to set the status line **mode** (preset) for the current session.

Context:
- Modes are defined in `~/.claude/statusline.modes`.
- The current session id is in the env var `$CLAUDE_CODE_SESSION_ID`.
- The helper `~/.claude/statusline-mode.sh` resolves a mode and writes a per-session conf
  (`~/.claude/statusline.sessions/<id>.conf`) that the status line reads for this session only.
- The global default (for new sessions) is managed separately with `slconfig` in a terminal.

Argument the user passed (may be empty): `$ARGUMENTS`

Do exactly this, then stop — keep your reply to 1-2 lines:

1. If `$ARGUMENTS` is empty or `list`:
   - Run `bash ~/.claude/statusline-mode.sh --list`.
   - Show the user the available modes (name + description) and which one this session is on, then
     tell them to pick with `/mode <name>`.
2. If `$ARGUMENTS` is `clear`, `default`, or `reset`:
   - Run `bash ~/.claude/statusline-mode.sh --clear` and confirm this session reverts to the global default.
3. Otherwise treat `$ARGUMENTS` as a mode name and run:
   `bash ~/.claude/statusline-mode.sh "$ARGUMENTS"`
   - On success, confirm this session now uses that mode (it applies on the next status line refresh).
   - If it reports "Unknown mode", show the listed available modes so they can retry.

Do NOT edit any files yourself — always go through `statusline-mode.sh` so the logic stays in one place.
