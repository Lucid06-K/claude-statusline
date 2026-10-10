---
description: Switch the status line preset (mode) for THIS Claude session
---

Set the status line mode (preset) for the current session.

Context:
- Modes live in `~/.claude/statusline.modes` as `name|description|ON-keys` (`ALL` = everything, `NONE` = nothing);
  `~/.claude/statusline.picker` is the curated picker list (`slconfig` -> g).
- `bash ~/.claude/statusline-mode.sh` does every write. Subcommands: `<mode>`, `--picker`, `--list`, `--show`,
  `--clear` (also `clear` / `default` / `reset`), `--global <mode>`.
- It writes `~/.claude/statusline.sessions/$CLAUDE_CODE_SESSION_ID.conf`; the renderer prefers that over the
  global `~/.claude/statusline.conf` (managed by `slconfig`). The change shows on the next status line refresh.

Argument the user passed (may be empty): `$ARGUMENTS`

## Empty (or `list` / `pick`): the picker
Bare `/mode` means the picker: call `AskUserQuestion`; never print the modes as text.
1. `bash ~/.claude/statusline-mode.sh --picker` prints `name|description` lines: the curated modes minus the one
   this session is on, capped at 4 (AskUserQuestion's option limit).
2. Call `AskUserQuestion` with one question, header `Mode`, one option per line: `label` = the name,
   `description` = the description. If `--picker` prints nothing, fall back to `--list` and offer up to 4.
3. Run `bash ~/.claude/statusline-mode.sh "<chosen name>"` and confirm in one line.

## `clear` / `default` / `reset`
Run `bash ~/.claude/statusline-mode.sh --clear` and confirm the session follows the global default again.

## Otherwise (a mode name)
Run `bash ~/.claude/statusline-mode.sh "$ARGUMENTS"` and confirm in one line; on "Unknown mode", open the picker.

Gotchas:
- Never edit conf files directly. The renderer parses strict `KEY=0/1` lines: unknown keys are ignored and a
  missing key shows that element ON, except `SL_MODEL_LIMIT` (off by default).
- Without `$CLAUDE_CODE_SESSION_ID` (set in the Bash tool here, absent in a plain terminal or hook) the script
  writes the GLOBAL default instead and says so; read its confirmation line before reporting.
- Every write deletes session confs older than 7 days, so a week-old session loses its override on the next
  `/mode` from any session.
- `--picker` hides the effective mode (the global default's mode when this session has no override), so the
  `--list` fallback only fires when the modes file is empty or every curated mode equals the current one.
