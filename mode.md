---
description: Switch the status line preset (mode) for THIS Claude session
---

Set the status line **mode** (preset) for the current session.

Context:
- Modes are defined in `~/.claude/statusline.modes`.
- The current session id is in `$CLAUDE_CODE_SESSION_ID`.
- `~/.claude/statusline-mode.sh` resolves a mode and writes a per-session conf
  (`~/.claude/statusline.sessions/<id>.conf`) the status line reads for this session only.
- The global default is managed separately with `slconfig`.

Argument the user passed (may be empty): `$ARGUMENTS`

## If `$ARGUMENTS` is empty (or `list` / `pick`) → SHOW THE PICKER

**You MUST open an interactive picker using the `AskUserQuestion` tool. Do NOT print the
modes as a text list, and do NOT answer in prose — the whole point of bare `/mode` is the picker.**

1. Run `bash ~/.claude/statusline-mode.sh --picker` → it prints `name|description` lines
   (the user's curated modes, current one already excluded, capped at 4).
2. Run `bash ~/.claude/statusline-mode.sh --show` → note the current mode (context only).
3. **Call `AskUserQuestion`** with a single question, header `Mode`, and **one option per
   `--picker` line**: `label` = the name, `description` = the description, and `preview` =
   a short plain-text sketch of that mode's status line. (If `--picker` returns nothing,
   fall back to `bash ~/.claude/statusline-mode.sh --list` and offer up to 4 modes.)
4. After the user picks, run `bash ~/.claude/statusline-mode.sh "<chosen name>"` and confirm
   in one short line.

## If `$ARGUMENTS` is `clear` / `default` / `reset`

Run `bash ~/.claude/statusline-mode.sh --clear` and confirm the session reverts to the global default.

## Otherwise (a mode name was given)

Run `bash ~/.claude/statusline-mode.sh "$ARGUMENTS"`. On success confirm in one line; if it
reports "Unknown mode", call `AskUserQuestion` with the available modes so they can pick.

Never edit files directly — always go through `statusline-mode.sh`.
