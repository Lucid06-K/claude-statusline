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

`install.sh` symlinks the two scripts into `~/.claude/`. Then:

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

## Configure — `slconfig`

Run `slconfig` (or `bash ~/.claude/statusline-config.sh`) for an interactive menu.

**Main menu**
- `number(s)` — toggle elements on/off (e.g. `3` or `2 7 9`)
- `m` — open the **Modes** menu
- `a` / `n` — all on / all off
- `?N` — explain element N
- `p` — preview against sample data
- `q` — save & quit

**Modes** (`m`) — named presets:
- `number` — apply a mode
- `c` — create a new mode from scratch
- `eN` — edit which elements mode N includes
- `dN` — delete mode N
- `s` — save your current toggles as a new mode

**Mode editor** (`c` / `eN`): `number(s)` toggle · `r` rename · `t` description · `p` preview · `s` save · `b` cancel

Seeded modes: `full`, `work`, `cost`, `minimal`, `focus`, `zen`.

## Files

| Path | Role |
|---|---|
| `statusline-command.sh` | The status line renderer (Claude Code pipes JSON to stdin) |
| `statusline-config.sh` | Interactive configurator |
| `~/.claude/statusline.conf` | Element toggles (managed by the configurator) |
| `~/.claude/statusline.modes` | Mode presets (managed by the configurator) |

The two `.conf`/`.modes` files are per-machine user data and live in `~/.claude/`, not in this repo.

## How it works

Claude Code invokes the status line command on each render, piping a JSON blob (model, effort,
context window, cost, rate limits, etc.) to stdin. `statusline-command.sh` parses it with `jq`,
builds each segment, and honors the toggles in `~/.claude/statusline.conf`. The configurator
just reads/writes that conf and the modes file.
