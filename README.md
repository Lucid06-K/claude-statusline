<div align="center">

# ◴ claude-statusline

**A configurable, good-looking status line for [Claude Code](https://claude.com/claude-code).**
Pick what shows, group it into **modes**, and switch modes per session — all from an arrow-key menu, no config-file editing.

![For Claude Code](https://img.shields.io/badge/for-Claude%20Code-d77757)
![macOS · Linux](https://img.shields.io/badge/macOS%20%C2%B7%20Linux-555)
![Built with bash](https://img.shields.io/badge/built%20with-bash-4EAA25?logo=gnubash&logoColor=white)
![Dependencies](https://img.shields.io/badge/deps-jq-blue)
![License](https://img.shields.io/badge/license-Apache--2.0-blue)

</div>

```
📁 Projects/petpak | feat/vet ⇡2 | Opus 4.8 ⚡ | xhigh | »«▕█████░▏ 88% ⚠ | ↓1.9M ↑42k | 5h ▕██████▏ 100% ⟳ 46m | $32.00/h | $6.40 | ⏱ 12m | 19:02
```

Everything is colour-coded, and most segments stay hidden until they're relevant — so a calm session reads short:

```
📁 ~ | Opus 4.8 | high | »«▕█░░░░░▏ 5% | $1.20/h | $0.01 | ⏱ 4s | 19:03
```

---

## Why you'll like it

| | |
|---|---|
| 🎨 **Looks the part** | Truecolor, the model in Claude's brand orange, effort colours matched to Claude Code's own `/effort` selector. |
| 🧩 **Modes, not fiddling** | Bundle the segments you want into named presets. Set a default for new sessions; switch the current session with `/mode`. |
| 🎛️ **Fully configurable** | An arrow-key TUI (`slconfig`) toggles 17 elements and builds modes — with a live preview. No file editing. |
| 📊 **Surfaces what matters** | Context meter, rolling rate-limit meters, burn rate, cost, tokens — synced across sessions, hidden until they count. |
| 🪶 **Featherweight** | One small bash script per render. Only `jq` required. No daemon, no `sudo`. |

---

## Contents

- [Install](#install) · [What it shows](#what-it-shows)
- [Modes](#modes) — [`slconfig`](#slconfig--the-default-for-new-sessions) · [`/mode`](#mode--per-session) · [the picker](#the-mode-picker)
- [Element reference](#element-reference) · [Customising](#customising)
- [How it works](#how-it-works) · [Updating](#updating) · [Versioning](#versioning) · [Uninstall](#uninstall) · [Requirements](#requirements) · [Security](#security) · [License](#license)

---

## Install

> 📦 **You need `git` and `jq`.** Check with `git --version` and `jq --version`.
> On macOS: `xcode-select --install` (git) and `brew install jq`. On Debian/Ubuntu: `sudo apt install git jq`.

```sh
git clone https://github.com/Lucid06-K/claude-statusline.git
cd claude-statusline && ./install.sh
```

That's it. `install.sh` is **idempotent** and **backs up before changing anything**:

| Step | What it does |
|---|---|
| 🔗 **Symlinks** the scripts into `~/.claude/` | the repo stays the source of truth — `git pull` to update, live |
| ⌨️ Installs the **`/mode`** command | into `~/.claude/commands/` |
| 📊 Sets **`.statusLine`** in `~/.claude/settings.json` | wires the status line (via `jq`) |
| 🅰️ Adds the **`slconfig`** alias | to `~/.zshrc` (or `~/.bashrc`) |

Then **restart Claude Code**, run `source ~/.zshrc`, and you're set.

> A truecolor terminal (iTerm2, Ghostty, Warp, VS Code) gives exact colours; others fall back to 256/16-colour automatically.

### Already cloned it before?

```sh
cd claude-statusline
git pull          # fetch the latest (scripts are symlinked, so this updates them live)
./install.sh      # safe to re-run; refreshes the wiring, keeps your modes & settings
```

---

## What it shows

The line is built from independent **elements**, each colour-coded and individually toggleable:

```
📁 Projects/petpak │ feat/vet ⇡2 │ Opus 4.8 ⚡ │ 🧠⨯ │ xhigh │ ✎ Explanatory │ »«▕█████░▏ 88% ⚠ │ ↓1.9M ↑42k │ 5h ▕██████▏ 100% ⟳ 46m │ 7d ▕████░░▏ 72% │ $32.00/h │ $6.40 │ ⏱ 12m │ 19:02
└ dir ──────────┘ └ git ──────┘ └ model+fast┘ └think┘ └effort┘ └ output style ┘ └ context+warn ┘ └ tokens ─┘ └ 5h limit ───────────┘ └ 7d limit ──────┘ └ burn ─┘ └ cost┘ └ timer┘ └ clock
```

Most are hidden unless they matter: the **context warning** (`⚠`) only at ≥85%, the **7-day meter** only ≥50%, **reset countdowns** (`⟳`) only when high, **`⚡`** only in fast mode, **`🧠⨯`** only when thinking is off, **`✎`** only for a non-default output style. See the [full reference](#element-reference).

---

## Modes

A **mode** is a named preset of which elements show — e.g. `full`, `work`, `cost`, `minimal`, `focus`, `zen` (all editable). Modes are managed in two places:

### `slconfig` — the default for new sessions

Run `slconfig` for an arrow-key menu. The highlighted mode previews its full status line underneath; a `·/mode` tag marks modes that appear in the `/mode` picker.

```
  Claude Code status line — Modes
  default for new sessions: full        ★ default · ·/mode = in picker
  ──────────────────────────────────────────────────────────
   ★ full       Everything on                              ·/mode
     work       Coding essentials — path, git, model…      ·/mode
     cost       Watch spend & rate limits                  ·/mode
     minimal    Path, git, model, clock                    ·/mode
     focus      Just enough to stay oriented
     zen        Nothing — a clean, empty line
  ──────────────────────────────────────────────────────────
     Configure /mode picker ▸
     + Create new mode
     Quit
  ──────────────────────────────────────────────────────────
  render  📁 ~ | Opus 4.8 | high | »«▕███░░░▏ 30% | $1.20/h | 19:02
  ↑/↓ move · enter set default · g /mode picker · e edit · c new · d delete · p preview · q quit
```

- **↑/↓** move · **Enter** make the highlighted mode the **default for new sessions**
- **g** choose which modes appear in the `/mode` picker · **e** edit · **c** create · **d** delete · **p** preview · **q** quit

Editing or creating opens the **element editor** — the one place individual on/off lives:

```
  ↑/↓ move · enter toggle · ? explain · r rename · t desc · p preview · s save · esc cancel
```

### `/mode` — per session

Inside Claude Code, switch **only the current session** without touching others:

| Command | Effect |
|---|---|
| `/mode` | pop an interactive picker (your curated modes) |
| `/mode <name>` | apply a mode directly — even one not in the picker |
| `/mode clear` | revert this session to the global default |

This works because Claude Code exposes `$CLAUDE_CODE_SESSION_ID`, which matches the `session_id` the status line receives — so `/mode` writes a per-session config the renderer prefers for that session only.

### The `/mode` picker

The in-Claude `/mode` picker is the interactive question UI (the closest equivalent to the native `/effort` selector). It holds **up to 5** modes — and since switching to the mode you're already on is a no-op, your current mode is hidden, leaving the **4** alternatives the picker can display. Curate it in `slconfig` → **g**.

---

## Element reference

Toggle any of these in the `slconfig` editor; colours adapt to your terminal.

| Element | Looks like | Shows / when |
|---|---|---|
| **Directory** | `📁 Projects/petpak` | working dir — `~` for home, `~/name` under home, else last two path segments |
| **Git status** | `feat/vet ⇡2` | branch · `*` if dirty · `⇡`/`⇣` ahead of / behind upstream |
| **Model name** | `Opus 4.8` | active model, in Claude's brand orange |
| **Fast-mode flag** | `⚡` | only while `/fast` is on |
| **Thinking off** | `🧠⨯` | only when extended thinking is disabled |
| **Reasoning effort** | `xhigh` | effort level, coloured like the `/effort` selector |
| **Output style** | `✎ Explanatory` | only when the output style isn't `default` |
| **Context meter** | `»«▕█████░▏ 88%` | context-window fill; bar green → yellow → red |
| **Context warning** | `⚠` | appended once context ≥85% (near auto-compact) |
| **5-hour limit** | `5h ▕█░░░░░▏ 20% ⟳ 2h35m` | rolling 5h usage; `⟳` reset countdown at ≥80% |
| **7-day limit** | `7d ▕████░░▏ 72%` | rolling 7d usage; appears only ≥50% |
| **Burn rate** | `$11.20/h` | spend per active hour |
| **Session cost** | `$6.40` | total spent this session |
| **Cost color** | *(tints `$`)* | dim < \$2 · yellow ≥ \$2 · red ≥ \$5 |
| **Session timer** | `⏱ 12m` | wall-clock since the session began |
| **Tokens** | `↓37k ↑264` | input / output tokens this session (k/M) |
| **Clock** | `19:02` | current time |

> **Rate-limit sync** — usage only climbs within a window, so the meters record the highest value any session has seen (keyed by reset time) and show that everywhere — no drift between sessions.

---

## Customising

- **Modes** — create/edit/delete entirely in `slconfig`; stored in `~/.claude/statusline.modes` (hand-editable: `name|description|ON-keys`, or `ALL`/`NONE`).
- **`/mode` picker** — `slconfig` → **g** (up to 5 modes).
- **Thresholds** — the cost tint (`$2`/`$5`), context-warning cutoff (`85%`), and 7-day reveal (`50%`) are plain constants near the top of the relevant segment in `statusline-command.sh`.
- **Compaction symbol** — the context meter is prefixed with `»«`; change it in one line in `statusline-command.sh`.

---

## How it works

Claude Code invokes the status line command on every render, piping a JSON blob (model, effort, context window, cost, rate limits, **session id**, output style, thinking, …) to **stdin**. `statusline-command.sh` parses it with `jq` and builds each enabled segment.

**Config precedence**, per render:

```
explicit $SL_CONF (previews)  →  per-session conf (set by /mode)  →  global default (set by slconfig)
```

| Path | Role |
|---|---|
| `statusline-command.sh` | the renderer |
| `statusline-config.sh` | the mode manager / configurator (`slconfig`) |
| `statusline-mode.sh` | applies a mode to a conf (used by `/mode`) |
| `statusline-update.sh` | git-based updater (used by `slconfig` → Updates) |
| `mode.md` | the `/mode` slash command |
| `~/.claude/statusline.conf` | global default (managed by `slconfig`) |
| `~/.claude/statusline.modes` | mode presets |
| `~/.claude/statusline.picker` | which modes appear in `/mode` |
| `~/.claude/statusline.sessions/<id>.conf` | per-session overrides (managed by `/mode`) |

The `.conf` / `.modes` / `.picker` / `.sessions` files are per-machine user data under `~/.claude/`, not in this repo. Written for **bash 3.2** (stock macOS) — no associative arrays, no `mapfile`.

---

## Updating

Because the scripts are symlinked from the checkout, an update is just a fast-forward of the repo. Do it from the **`slconfig` menu** (`u` → **Updates**) or the command line:

```sh
~/.claude/statusline-update.sh          # check + update to the latest
~/.claude/statusline-update.sh --status # version + auto-update state
```

Turn on **once-a-day auto-update** in `slconfig` → **Updates** → *Auto-update* (off by default). When on, the status line fires a throttled **background** check once a day and fast-forwards if there's anything new — it never blocks or slows a render.

**Updates are kept safe:**

- **`git pull --ff-only`** over **HTTPS**, pinned to this repository — a fast-forward can't rewrite or clobber local history, and aborts cleanly if you've made local edits.
- **Syntax-checked** after pulling; if anything fails `bash -n`, the update reports it (and a fast-forward leaves your working tree on whole, signed-by-git commits — content is hash-verified by git itself).
- **User space only — never `sudo`.** Nothing is downloaded outside the repo.

> First install aside (you're trusting the initial clone), every later update is anchored to git's content hashing over HTTPS to the pinned origin.

## Versioning

[Semantic Versioning](https://semver.org), single rolling track on `main`:

| Bump | When | Example |
|---|---|---|
| **MAJOR** | a breaking change to the conf/mode format or how the status line is wired — may require re-creating modes or re-running `install.sh` | `1.x → 2.0.0` |
| **MINOR** | new elements, modes, or features — backward-compatible | `1.0 → 1.1.0` |
| **PATCH** | bug fixes, docs, polish — no change to existing setups | `1.1.0 → 1.1.1` |

The version lives in the repo-root [`VERSION`](VERSION) file and is reported by `statusline-update.sh --status` (alongside the git commit). Changes are recorded in the [CHANGELOG](CHANGELOG.md).

## Uninstall

Remove the symlinks (`~/.claude/statusline-*.sh`), the `/mode` command (`~/.claude/commands/mode.md`), the `statusLine` block in `~/.claude/settings.json`, and the `slconfig` alias from your shell rc. Your modes/config files under `~/.claude/` can be deleted too.

## Requirements

- [Claude Code](https://claude.com/claude-code)
- `bash`, `jq`, `git`, and standard `awk`/`date` (all preinstalled on macOS/Linux except `jq`)
- A truecolor terminal for exact colours (optional — degrades gracefully)

## Security

Runs entirely in user space (no `sudo`), reads-not-executes the JSON Claude Code pipes in, and updates fast-forward-only over HTTPS pinned to this repo. Found something? Please report it privately — see the [security policy](SECURITY.md).

## License

[Apache License 2.0](LICENSE) — © 2026 Lucid06-K (see [NOTICE](NOTICE)).
