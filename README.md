<div align="center">

# ◴ claude-statusline

**A configurable, good-looking status line for [Claude Code](https://claude.com/claude-code).**
Pick what shows, group it into **modes**, and switch modes per session — all from an arrow-key menu, no config-file editing.

![For Claude Code](https://img.shields.io/badge/for-Claude%20Code-d77757)
![macOS · Linux · Windows](https://img.shields.io/badge/macOS%20%C2%B7%20Linux%20%C2%B7%20Windows-555)
![Built with bash](https://img.shields.io/badge/built%20with-bash-4EAA25?logo=gnubash&logoColor=white)
![Windows PowerShell](https://img.shields.io/badge/windows-PowerShell%205.1%2B-5391FE)
![Dependencies](https://img.shields.io/badge/deps-jq%20%28bash%29%20%C2%B7%20none%20%28Windows%29-blue)
![License](https://img.shields.io/badge/license-Apache--2.0-blue)

</div>

```
📁 Projects/poyona | feat/vet ⇡2 | Opus 4.8 ⚡ | xhigh | »«▕█████▒▏ 88% ⚠ | ↓1.9M ↑42k | 5h ▕██████▏ 100% ⟳ 46m | $32.00/h | $6.40 | ⏱ 12m | 19:02
```

Everything is colour-coded, and most segments stay hidden until they're relevant — so a calm session reads short:

```
📁 ~ | Opus 4.8 | high | »«▕█▒▒▒▒▒▏ 12% | $1.20/h | $0.01 | ⏱ 4s | 19:03
```

---

## Why you'll like it

| | |
|---|---|
| 🎨 **Looks the part** | Truecolor, the model in Claude's brand orange, effort colours matched to Claude Code's own `/effort` selector. |
| 🧩 **Modes, not fiddling** | Bundle the segments you want into named presets. Set a default for new sessions; switch the current session with `/mode`. |
| 🎛️ **Fully configurable** | An arrow-key TUI (`slconfig`) toggles 17 elements and builds modes — with a live preview. No file editing. |
| 📊 **Surfaces what matters** | Context meter, rolling rate-limit meters, burn rate, cost, tokens — synced across sessions, hidden until they count. |
| 🪶 **Featherweight** | One small script per render — bash + `jq` on macOS/Linux, dependency-free PowerShell on Windows. No daemon, no `sudo`. |
| 🪟 **Windows native** | A full PowerShell port in [`windows/`](windows) — same features, same config files, no `jq`, no WSL. |

---

## Contents

- [Install](#install) · [What it shows](#what-it-shows)
- [Modes](#modes) — [`slconfig`](#slconfig--the-default-for-new-sessions) · [`/mode`](#mode--per-session) · [the picker](#the-mode-picker)
- [Element reference](#element-reference) · [Customising](#customising)
- [How it works](#how-it-works) · [Updating](#updating) · [Versioning](#versioning) · [Uninstall](#uninstall) · [Requirements](#requirements) · [Security](#security) · [License](#license)

---

## Install

### macOS / Linux

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

### Windows

> 📦 **Nothing extra to install.** Runs on the built-in Windows PowerShell 5.1 — or PowerShell 7 (`pwsh`) if you have it (auto-detected, slightly snappier). No `jq`, no WSL. `git` is optional (used by the git segment and the updater).

```powershell
git clone https://github.com/Lucid06-K/claude-statusline.git
cd claude-statusline
powershell -ExecutionPolicy Bypass -File windows\install.ps1
```

**No git?** Download **`claude-statusline-windows.zip`** from the [latest release](https://github.com/Lucid06-K/claude-statusline/releases/latest), extract it, and run the same `install.ps1` command from the extracted folder.

`install.ps1` is **idempotent** and **backs up before changing anything**:

| Step | What it does |
|---|---|
| 📄 **Copies** the scripts into `%USERPROFILE%\.claude\` | Windows symlinks need admin, so the updater re-copies after every update instead |
| ⌨️ Installs the **`/mode`** command | generated with absolute paths, into `~\.claude\commands\` |
| 📊 Sets **`.statusLine`** in `~\.claude\settings.json` | native JSON handling — no `jq` needed |
| 🅰️ Adds the **`slconfig`** function | to your PowerShell profile(s) |

Then **restart Claude Code**, open a **new** PowerShell window (so the profile reloads), and you're set.

> A truecolor terminal (iTerm2, Ghostty, Warp, VS Code, **Windows Terminal**) gives exact colours; others fall back to 256/16-colour automatically.

### Already cloned it before?

macOS / Linux — the scripts are symlinked, so a pull updates them live:

```sh
cd claude-statusline
git pull
./install.sh      # safe to re-run; refreshes the wiring, keeps your modes & settings
```

Windows — the scripts are copies, so re-run the installer after pulling (or just use `slconfig` → **Updates**, which does both):

```powershell
cd claude-statusline
git pull
powershell -ExecutionPolicy Bypass -File windows\install.ps1
```

---

## What it shows

The line is built from independent **elements**, each colour-coded and individually toggleable. With everything showing:

```
📁 Projects/poyona | feat/vet* ⇡2 | Opus 4.8 ⚡ | 🧠⨯ | xhigh | ✎ Explanatory | »«▕█████▒▏ 88% ⚠ | ↓1.9M ↑42k | 5h ▕██████▏ 100% ⟳ 46m | 7d ▕████▒▒▏ 72% | $32.00/h | $6.40 | ⏱ 12m | 19:02
```

In order: **directory** · **git** (branch, `*` dirty, `⇡⇣` ahead/behind) · **model** + `⚡` fast mode · `🧠⨯` thinking off · **effort** · `✎` **output style** · **context meter** + `⚠` warning · `↓↑` **tokens** · **5h** and **7d rate limits** (`⟳` reset countdown) · **burn rate** · **cost** · `⏱` **timer** · **clock**.

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
     Updates ▸
     + Create new mode
     Quit
  ──────────────────────────────────────────────────────────
  render  📁 ~ | Opus 4.8 (1M context) ⚡ | xhigh | »«▕█████▒▏ 88% ⚠ | 5h ▕██████▏ 100% ⟳ 47m | 7d ▕████▒▒▏ 72% | $32.00/h | $6.40 | ⏱ 0s | 19:02
  ↑/↓ move · enter set default · g picker · u updates · e edit · c new · d delete · p preview · q quit
```

- **↑/↓** move · **Enter** make the highlighted mode the **default for new sessions**
- **g** choose which modes appear in the `/mode` picker · **u** updates · **e** edit · **c** create · **d** delete · **p** preview · **q** quit

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
| **Directory** | `📁 Projects/poyona` | working dir — `~` for home, `~/name` under home, else last two path segments |
| **Git status** | `feat/vet ⇡2` | branch · `*` if dirty · `⇡`/`⇣` ahead of / behind upstream |
| **Model name** | `Opus 4.8` | active model, in Claude's brand orange |
| **Fast-mode flag** | `⚡` | only while `/fast` is on |
| **Thinking off** | `🧠⨯` | only when extended thinking is disabled |
| **Reasoning effort** | `xhigh` | effort level, coloured like the `/effort` selector |
| **Output style** | `✎ Explanatory` | only when the output style isn't `default` |
| **Context meter** | `»«▕█████▒▏ 88%` | context-window fill; bar green → yellow → red |
| **Context warning** | `⚠` | appended once context ≥85% (near auto-compact) |
| **5-hour limit** | `5h ▕█▒▒▒▒▒▏ 20%` | rolling 5h usage; a `⟳` reset countdown appears at ≥80% |
| **7-day limit** | `7d ▕████▒▒▏ 72%` | rolling 7d usage; appears only ≥50% |
| **Burn rate** | `$11.20/h` | spend per active hour |
| **Session cost** | `$6.40` | total spent this session |
| **Cost color** | *(tints `$`)* | dim < \$2 · yellow ≥ \$2 · red ≥ \$5 |
| **Session timer** | `⏱ 12m` | wall-clock since the session began |
| **Tokens** | `↓37k ↑264` | ↓ tokens in the context window right now (cache reads included), ↑ the last response (k/M) |
| **Clock** | `19:02` | current time |

> **Rate-limit sync** — the 5h and 7d windows roll, so usage falls again as old activity ages out and the reading Claude Code sends is always the one shown. Each reading is cached (keyed by reset time) purely so a session that has none yet — `rate_limits` is absent until that session's first API response — can still show the account-wide number instead of a gap. A cached value is never used past its own reset.

---

## Customising

- **Modes** — create/edit/delete entirely in `slconfig`; stored in `~/.claude/statusline.modes` (hand-editable: `name|description|ON-keys`, or `ALL`/`NONE`).
- **`/mode` picker** — `slconfig` → **g** (up to 5 modes).
- **Thresholds** — the cost tint (`$2`/`$5`), context-warning cutoff (`85%`), and 7-day reveal (`50%`) are plain constants near the top of the relevant segment in `statusline-command.sh` (or `windows/statusline-command.ps1`).
- **Compaction symbol** — the context meter is prefixed with `»«`; change it in one line in the renderer.

---

## How it works

Claude Code invokes the status line command on every render, piping a JSON blob (model, effort, context window, cost, rate limits, **session id**, output style, thinking, …) to **stdin**. `statusline-command.sh` parses it with `jq` and builds each enabled segment; on Windows, `statusline-command.ps1` does the same with PowerShell's native JSON parsing.

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
| `windows/*.ps1` | native PowerShell ports of all of the above + `install.ps1` (no `jq`) |
| `~/.claude/statusline.conf` | global default (managed by `slconfig`) |
| `~/.claude/statusline.modes` | mode presets |
| `~/.claude/statusline.picker` | which modes appear in `/mode` |
| `~/.claude/statusline.sessions/<id>.conf` | per-session overrides (managed by `/mode`) |

The `.conf` / `.modes` / `.picker` / `.sessions` files are per-machine user data under `~/.claude/`, not in this repo. Written for **bash 3.2** (stock macOS) — no associative arrays, no `mapfile`. The Windows ports target **PowerShell 5.1** (stock Windows 10/11, pwsh 7 compatible) and read/write the **exact same config-file formats**.

---

## Updating

Because the scripts are symlinked from the checkout, an update is just a fast-forward of the repo. Do it from the **`slconfig` menu** (`u` → **Updates**) or the command line:

```sh
~/.claude/statusline-update.sh          # check + update to the latest
~/.claude/statusline-update.sh --status # version + auto-update state
```

On Windows the updater additionally re-copies the scripts into `~\.claude\` after pulling (they're copies, not symlinks):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\statusline-update.ps1"           # check + update
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\statusline-update.ps1" --status  # version + auto-update state
```

Turn on **once-a-day auto-update** in `slconfig` → **Updates** → *Auto-update* (off by default). When on, the status line fires a throttled **background** check once a day and fast-forwards if there's anything new — it never blocks or slows a render.

**Updates are kept safe:**

- **`git pull --ff-only`** over **HTTPS**, pinned to this repository — a fast-forward can't rewrite or clobber local history, and aborts cleanly if you've made local edits.
- **Syntax-checked** after pulling; if anything fails `bash -n` (or the PowerShell parser on Windows), the update reports it (and a fast-forward leaves your working tree on whole, signed-by-git commits — content is hash-verified by git itself).
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

**macOS / Linux:** remove the symlinks (`~/.claude/statusline-*.sh`), the `/mode` command (`~/.claude/commands/mode.md`), the `statusLine` block in `~/.claude/settings.json`, and the `slconfig` alias from your shell rc.

**Windows:** remove the copies (`~\.claude\statusline-*.ps1` and `~\.claude\statusline.repo`), the `/mode` command (`~\.claude\commands\mode.md`), the `statusLine` block in `~\.claude\settings.json`, and the `slconfig` function from your PowerShell profile(s).

Your modes/config files under `~/.claude/` can be deleted too.

## Requirements

- [Claude Code](https://claude.com/claude-code)
- **macOS / Linux:** `bash`, `jq`, `git`, and standard `awk`/`date` (all preinstalled except `jq`)
- **Windows:** Windows PowerShell 5.1 (built into Windows 10/11) or PowerShell 7 — no other dependencies; `git` optional (git segment + updates)
- A truecolor terminal for exact colours (optional — degrades gracefully; Windows Terminal is detected automatically)

## Security

Runs entirely in user space (no `sudo` on macOS/Linux, no elevation on Windows), reads-not-executes the JSON Claude Code pipes in, parses its conf as inert `KEY=0/1` pairs on every platform, and updates fast-forward-only over HTTPS pinned to this repo. Found something? Please report it privately — see the [security policy](SECURITY.md).

## License

[Apache License 2.0](LICENSE) — © 2026 Lucid06-K (see [NOTICE](NOTICE)).
