# Changelog

All notable changes to **claude-statusline**. This project follows
[Semantic Versioning](https://semver.org) on a single rolling `main` track —
see [Versioning](README.md#versioning).

## 1.1.1 — 2026-07-04

Bug-fix release.

### Security / data safety
- The status line no longer `source`s its conf file — a mode name is written into
  that conf, so a crafted name executed arbitrary shell on **every render**. Toggles
  are now parsed as strict `KEY=0/1`; the mode name is an inert display string.
- Mode deletion matches the exact first field (awk) instead of using the name as a
  grep regex, which could match unrelated lines or wipe the whole modes file.
- `|` (the field delimiter) and a leading `#` are stripped from mode names/descriptions
  so they can't corrupt the modes file (which had rendered a blank status line).

### slconfig TUI
- Ctrl-C exits cleanly and restores the terminal (it was interpreted as Enter — firing
  the focused action, e.g. overwriting the default mode — and left echo disabled).
- Right/Left/Home/End/Delete/PgUp no longer quit the editor (and discard edits); only a
  bare ESC is Esc.
- Renaming a mode updates the /mode picker file too (renamed mode no longer vanishes).
- Deleting the current default clears `SL_MODE` in the conf (header no longer names a
  deleted mode).

### Performance / correctness
- The hot path extracts all fields in **one** `jq` call instead of 17 (removing ~17
  fork/exec per render).
- Reset countdown (⟳) shows only at ≥80%, matching the docs; fixed the "10-cell bar"
  help text (the bar is 6 cells).
- `install.sh` seeds the mode presets, so `/mode` works on a fresh install.

## 1.1.0 — 2026-06-21

- **License & policy:** relicensed to **Apache-2.0** (+ `NOTICE`); added `SECURITY.md`
  (private vulnerability reporting, scope, and an honest trust note for the git-based update model).
- **Fix — `/mode` picker now reaches fresh installs.** The command was *copied* into
  `~/.claude/commands/` (so `git pull` never refreshed it) and the public repo's copy was
  stale; it's now **symlinked**, kept in sync, and the picker is **mandatory** in the command prompt.
- **Updater self-heals.** After each pull it re-links all `statusline-*.sh` scripts and the
  `/mode` command, so future fixes (and new/renamed scripts) propagate without re-running `install.sh`.

## 1.0.0 — Initial public release

- Configurable status line with **17 toggleable elements**: directory, git (±upstream),
  model (Claude orange), fast-mode `⚡`, thinking-off `🧠⨯`, reasoning effort, output style,
  context meter + `»«` compaction symbol + `⚠` warning, tokens, 5-hour / 7-day rate-limit meters,
  burn rate, session cost + escalation tint, session timer, clock.
- **Modes** (named presets) with an arrow-key configurator (`slconfig`): set the default for new
  sessions, create/edit/delete modes, and curate the `/mode` picker — all in-menu, with live preview.
- **Per-session switching** via the `/mode` slash command.
- Cross-session **rate-limit sync**; truecolor with 256/16-colour fallback.
- **One-command installer**; git-based **opt-in auto-update**.
