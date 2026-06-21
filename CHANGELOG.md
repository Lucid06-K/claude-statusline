# Changelog

All notable changes to **claude-statusline**. This project follows
[Semantic Versioning](https://semver.org) on a single rolling `main` track —
see [Versioning](README.md#versioning).

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
