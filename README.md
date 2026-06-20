# claude-statusline

A configurable status line for [Claude Code](https://claude.com/claude-code), with an
interactive CLI to toggle elements and manage presets ("modes") — no config-file editing required.

```
📁 Projects/petpak | feat/vet-portal-redesign | Opus 4.8 ⚡ | xhigh | ▕█████████░▏ 88% ⚠ | 5h ▕██████▏ 100% ⟳46m | 7d ▕████░░▏ 72% | $32.00/h | $6.40 | ⏱ 12m | 19:02
```

Everything is color-coded and most segments stay hidden until they're relevant, so a calm
session reads short:

```
📁 ~ | Opus 4.8 | high | ▕█░░░░░░░░░▏ 5% | 5h ▕█░░░░░▏ 20% | $1.20/h | $0.01 | ⏱ 4s | 19:03
```

## What it shows

| Element | Description |
|---|---|
| **Directory** | Working dir — `~` for home, `~/name` directly under home, else the last two path segments |
| **Git status** | Branch, `*` when dirty, `⇡N`/`⇣N` ahead of / behind upstream |
| **Model name** | Active model in Claude's brand orange |
| **Fast-mode flag** | `⚡` while `/fast` is active |
| **Reasoning effort** | `low/medium/high/xhigh/max`, colored to match Claude Code's effort selector |
| **Context meter** | Context-window bar + %, green → yellow → red |
| **Context warning** | `⚠` once context is near auto-compact (≥85%) |
| **5-hour limit** | Rolling 5-hour usage meter; reset countdown at ≥80% |
| **7-day limit** | Rolling 7-day usage meter; appears at ≥50% |
| **Burn rate** | Spend velocity, `$/active hour` |
| **Session cost** | Total `$` this session (tints with spend) |
| **Session timer** | `⏱` wall-clock since the session started |
| **Clock** | Current time |

## Install

```sh
git clone https://github.com/Lucid06-K/claude-statusline.git
cd claude-statusline
./install.sh
```

`install.sh` symlinks the scripts into `~/.claude/` and installs the `/mode` command. Then:

1. **Wire the status line** — in `~/.claude/settings.json`:
   ```json
   "statusLine": { "type": "command", "command": "bash ~/.claude/statusline-command.sh" }
   ```
2. **Add the configurator alias** to your shell rc (e.g. `~/.zshrc`):
   ```sh
   alias slconfig="bash ~/.claude/statusline-config.sh"
   ```

A truecolor terminal (iTerm2, Ghostty, Warp, VS Code) gives exact colors; others fall back to
256/16-color automatically.

## Modes

The unit of configuration is a **mode** — a named preset of which elements show. Seeded with
`full`, `work`, `cost`, `minimal`, `focus`, `zen` (all editable). Two places set them:

### `slconfig` — the default for *new* sessions

Run `slconfig` (arrow-key TUI). The main screen lists your modes; the highlighted one's full
status line previews live underneath.
- **↑/↓** move · **Enter** set the highlighted mode as the **default for new sessions**
- **e** edit a mode · **c** create one · **d** delete · **p** preview · **q** quit

Editing/creating opens the element editor (this is where individual on/off lives):
`↑/↓` move · `Enter` toggle · `r` rename · `t` description · `p` preview · `s` save · `esc` cancel

### `/mode` — this session only

Inside Claude Code, switch the **current session's** mode without touching others:
- `/mode <name>` — apply a mode to this session
- `/mode` — list modes and show the current one
- `/mode clear` — revert this session to the global default

This works because Claude Code exposes `$CLAUDE_CODE_SESSION_ID`; `/mode` writes a per-session
conf the status line prefers for that session.

## Files

| Path | Role |
|---|---|
| `statusline-command.sh` | The status line renderer (Claude Code pipes JSON to stdin) |
| `statusline-config.sh` | Mode manager / configurator (`slconfig`) |
| `statusline-mode.sh` | Applies a mode to a conf (used by `/mode`) |
| `mode.md` | The `/mode` slash command (installed to `~/.claude/commands/`) |
| `~/.claude/statusline.conf` | Global default (managed by `slconfig`) |
| `~/.claude/statusline.modes` | Mode presets (managed by the menu) |
| `~/.claude/statusline.sessions/<id>.conf` | Per-session overrides (managed by `/mode`) |

The `.conf` / `.modes` / `.sessions` files are per-machine user data under `~/.claude/`, not in this repo.

## How it works

Claude Code invokes the status line command on each render, piping a JSON blob (model, effort,
context window, cost, rate limits, **session id**, etc.) to stdin. `statusline-command.sh` parses
it with `jq` and builds each segment. Config precedence per render: an explicit `$SL_CONF`
(used for previews) → a per-session conf matching the JSON's `session_id` (set by `/mode`) →
the global `statusline.conf` (set by `slconfig`).
