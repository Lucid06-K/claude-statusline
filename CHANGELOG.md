# Changelog

All notable changes to **claude-statusline**. This project follows
[Semantic Versioning](https://semver.org) on a single rolling `main` track —
see [Versioning](README.md#versioning).

## 1.3.2 - 2026-09-29

Brings `/mode` in step with 1.3.0.

### Fixed
- **`/mode` never enabled the per-model weekly limit.** `statusline-mode.sh` carried its own key
  list, which 1.3.0 forgot to extend, so every conf it wrote lacked `SL_MODEL_LIMIT` and the
  renderer defaulted it to 0: `/mode full` (ALL) silently skipped the element and a `cost` preset
  naming the key had no effect. The key is in the list now. A conf without it still reads as off,
  so sessions that never asked for the element see no change. The PowerShell port has no
  per-model limit element yet, so its key lists are unchanged on purpose.
- `statusline-mode.sh` now applies the renderer's session-id check (`[A-Za-z0-9._-]`, else no id),
  so both agree on which per-session conf they use; the Windows port already did.

### Changed
- **`/mode` command text trimmed** (repo `mode.md`, mirrored in `windows/install.ps1`): the
  shouting paragraph added in b2191b3 (claude-commands d277c9b) for an older model is one plain
  sentence, the `--show` step is gone (`--picker` already excludes the current mode) and the
  picker no longer asks the model to invent a `preview` sketch. A real preview would need
  `statusline-config.sh`'s `render_sample` run once per option with its ANSI colour escapes and
  Unicode bars stripped, four renders per picker; dropping the field was the cheaper choice. The
  command now carries the gotchas that matter inside a session instead: no session id means a
  global write, session confs older than 7 days are garbage-collected on every write, and the
  picker hides the effective mode.
- Plain punctuation replaces the em dashes in the conf header comment and the no-session message.

### Upgrade note
- A `statusline.modes` file created before 1.3.0 has no `SL_MODEL_LIMIT` in its `cost` line; add
  it there (or through `slconfig`) to match `statusline.modes.example`. Leave customised presets
  as they are.

## 1.3.1 — 2026-08-26

Makes 1.3.0 actually fetch 🔑

### Fixed
- **The keychain lookup found the wrong item, so the fetch always came back tokenless.**
  Two generic-password items share the service name `Claude Code-credentials`: the one
  keyed to your username holds `claudeAiOauth`, and a second one (account `unknown`)
  holds only per-server `mcpOAuth` tokens. Looking up by service alone returned whichever
  the keychain handed back first, which was the MCP one. It now asks for the username
  account first, the way Claude Code itself does, and falls back to a service-only match.
- **`percent` is already 0-100, and was being halved-into-nonsense by the fraction
  heuristic.** The live response returns `{kind, group, is_active, percent, resets_at,
  scope, severity}` with `percent: 15`, so it is now used as-is; the 0-1 scaling applies
  only to the `utilization` alias, which is the field Claude Code reads elsewhere.
- **Reset countdowns never appeared.** `resets_at` arrives as
  `2026-09-01T14:00:00.246196+00:00`, and jq's `fromdateiso8601` rejects both the
  fractional seconds and the numeric offset, so every timestamp fell back to 0. Both are
  normalised away now and the offset is re-applied by hand.

## 1.3.0 — 2026-08-26

Per-model weekly limits (Fable / Opus / Sonnet) 📊

### Added
- **Per-model weekly limit element** (`SL_MODEL_LIMIT`, off by default). Renders the
  weekly cap for a specific model as a bar + %, e.g. `Fable ▕██▒▒▒▒▏ 34%`, with a `⟳`
  reset countdown at ≥80%, matching the 5h/7d meters. Claude Code's status-line payload
  cannot supply this: its `rate_limits` object is built from exactly two fields,
  `five_hour` and `seven_day` (verified in 2.1.246), while the per-model windows that
  `/usage` renders as *"Current week (Fable 5)"* only exist on its internal control
  protocol. So `statusline-usage.sh` (new) asks the same endpoint `/usage` does,
  `GET /api/oauth/usage`, using the OAuth token already in the login keychain.
  - Throttled to one fetch per 5 minutes across all sessions: the renderer claims the
    slot by stamping the throttle file *before* forking, so ten open sessions produce
    one request, not ten.
  - The fetch is detached and never blocks a render; the renderer only reads a small
    cache file. A cache older than an hour is ignored rather than shown stale.
  - The token is never printed, never written to disk, and reaches `curl` through a
    config file on stdin, so it stays out of the process argument list.
  - Parsing is deliberately shape-tolerant, and accepts either 0-1 or 0-100 values,
    because the endpoint is internal and undocumented. If its shape changes the element
    disappears instead of breaking the line.
  - `statusline-usage.sh --show` prints what was parsed, `--raw` the raw JSON (never the
    token), `--cache` the current cache. The first run needs one keychain approval.

### Fixed
- **A missing throttle file printed a shell error into the status line.** `read -r x <
  "$f" 2>/dev/null` applies its redirections left to right, so the failing input
  redirect wrote "No such file or directory" to the real stderr before `2>/dev/null`
  was ever installed. Both throttle reads are now wrapped as `{ read -r x < "$f"; }
  2>/dev/null`. Visible on the very first render after the auto-update check was
  enabled.

### Added (debugging)
- `~/.claude/statusline.dump` (touch the file to arm it) writes each render's raw stdin
  payload to `$TMPDIR/cc-statusline/dump-<session-id>.json`. One `[ -f ]` test per
  render when unarmed. Useful for checking what Claude Code actually sends, e.g. when
  the context meter disagrees with `/context`.

## 1.2.1 — 2026-08-24

Accuracy and render fixes 🎯

### Fixed
- **Wrong numbers whenever any field was absent.** The 17 payload fields were joined
  with tabs and read back with `IFS=$'\t'`, but tab is an IFS *whitespace* character:
  bash collapses runs of tabs and strips leading/trailing ones, so every field after an
  empty one shifted left by one. Claude Code omits fields routinely — `effort` only
  exists on reasoning models, `rate_limits` only after that session's first API response
  (and `five_hour` / `seven_day` are each optional on their own), and `used_percentage`
  is null until the first message — so on every session start the line showed a wrong
  context %, a wrong 5h %, a wrong cost and a wrong elapsed time, then silently corrected
  itself once the first response landed. Fields are now joined with US (U+001F), which is
  not IFS whitespace, and every value is scrubbed of US/CR/LF so none can forge a field
  boundary or a line break.
- **Rate-limit meters over-reported.** The cross-session cache kept the highest value
  seen per window on the premise that usage only climbs. The 5h and 7d windows roll, so
  usage genuinely falls as old activity ages out, and the meters stayed at the peak for
  the rest of the window. The payload reading now always wins; the cache only fills in
  for a session that has no reading yet, and never past its own reset.
- **Progress bars changed width as they filled.** `█` (U+2588) is East Asian Ambiguous
  and `░` (U+2591) is Neutral, so in any terminal, locale or font that widens ambiguous
  glyphs the bar grew as it filled and shifted everything after it. The empty cell is now
  `▒` (U+2592), ambiguous like the block and like both end caps, so the bar occupies the
  same columns at every fill level.
- **`⚠` pinned to text presentation** with U+FE0E — it has no default emoji presentation,
  so width calculations and terminals could disagree and smear the line when the
  near-compaction warning appeared.
- **Segment colours no longer cancel the host's dim.** Claude Code renders the status
  line inside `<Text dimColor>`; the script's `ESC[0m` resets switched that off partway
  through, so later segments rendered brighter. It now resets the foreground only
  (`ESC[39m`).
- **A non-numeric `resets_at`** would abort the countdown arithmetic and write a bash
  error to the status line's stderr; it is now validated before use.
- **Elapsed timer restarted on long sessions.** The start marker was pruned at
  `-mtime +2` on every render, deleting it out from under any session still running after
  two days. Pruning now happens only when a new session appears, at 14 days.
- **`ctx:` fallback** used `current_usage.input_tokens`, which excludes cache reads, and
  read as `ctx:2t` for a 92k-token context. It now uses `total_input_tokens`.
- **The configurator preview was corrupted** by the same field shift and its sample
  payload omitted five fields, so the Tokens, Output style and Thinking toggles appeared
  to do nothing. The sample is now complete.
- **`session_id` is validated** before being interpolated into a conf path or temp-file
  name.

### Changed
- **Renders are ~2.7x faster** (129ms -> 48ms). One `git status --porcelain=v2 --branch`
  replaces four git invocations, `--no-optional-locks` stops the status line taking
  `index.lock` several times a second against the user's own git commands, burn rate and
  cost colour are computed in the existing `jq` pass instead of forking `awk`, and the
  three `date` calls and the per-render `find` are gone.
- Token counts are documented for what they are: `↓` is what is in the context window
  right now (cache reads included) and `↑` is the most recent API response, not session
  totals.

## 1.2.0 — 2026-07-11

Windows support 🪟

### Added
- **Native Windows port** in [`windows/`](windows): PowerShell ports of the renderer, the
  `slconfig` TUI, `/mode` handling, and the updater, plus `windows/install.ps1`. Runs on stock
  Windows PowerShell 5.1 or pwsh 7 (auto-detected) — **no `jq`, no WSL, no admin**. Config
  files share the exact same formats across platforms.
- The Windows installer **copies** the scripts (symlinks need admin on Windows) and records the
  checkout path in `~\.claude\statusline.repo`; the updater re-copies after every fast-forward
  pull so updates still propagate. The `/mode` command is generated with absolute paths, and a
  `slconfig` function is added to the PowerShell profile(s).
- Truecolor is auto-enabled in Windows Terminal (`WT_SESSION`); legacy conhost gets ANSI (VT)
  enabled programmatically for the TUI, with 256/16-colour fallback elsewhere.
- A downloadable **`claude-statusline-windows.zip`** is attached to the GitHub release for
  git-less installs.

### Fixed / docs
- README example renders are accurate again: replaced the two-row segment diagram (emoji
  widths made the underline row misalign on GitHub) with a plain example line + ordered
  legend; corrected bar fills to match the real `(pct·width+50)/100` maths; added the missing
  `Updates ▸` row and `u` key hint to the `slconfig` screenshot; updated its stale preview
  line; removed the `⟳` countdown from the 20% 5-hour example (it only appears at ≥80%).
- The `slconfig` per-element preview for the 5-hour limit showed a countdown at 62%; it now
  previews 83%, matching the ≥80% behaviour.
- SECURITY.md still described the pre-1.1.1 `source`-based conf loading; it now documents the
  hardened parse-only behaviour on both platforms.

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
