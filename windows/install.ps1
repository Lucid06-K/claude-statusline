# Install claude-statusline on Windows. Run after cloning (or unzipping):
#   powershell -ExecutionPolicy Bypass -File windows\install.ps1
# - copies the scripts into %USERPROFILE%\.claude (Windows symlinks need admin,
#   so we copy; statusline-update.ps1 re-copies them after every update)
# - installs the /mode slash command (generated with absolute paths)
# - wires the status line into ~\.claude\settings.json (native JSON — no jq)
# - adds the `slconfig` function to your PowerShell profile(s)
# Re-running is safe (idempotent); settings.json is backed up before changes.
#
#   -Quiet        suppress progress output (used by the updater's self-heal)
#   -SkipProfile  don't touch PowerShell profiles

param([switch]$Quiet, [switch]$SkipProfile)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

function Say([string]$m) { if (-not $Quiet) { Write-Host $m } }

$SRC = $PSScriptRoot
$HOME_DIR = $env:USERPROFILE
if (-not $HOME_DIR) { $HOME_DIR = [Environment]::GetFolderPath('UserProfile') }
$DEST = Join-Path $HOME_DIR '.claude'
New-Item -ItemType Directory -Force -Path $DEST, (Join-Path $DEST 'commands') | Out-Null

# Engine: prefer pwsh (PowerShell 7 — faster startup, native UTF-8) when present,
# else Windows PowerShell 5.1, which every Windows 10/11 machine has.
$engine = if (Get-Command pwsh -ErrorAction SilentlyContinue) { 'pwsh' } else { 'powershell' }

# 1) scripts -> copies
foreach ($f in 'statusline-command.ps1', 'statusline-mode.ps1', 'statusline-config.ps1', 'statusline-update.ps1') {
  Copy-Item -LiteralPath (Join-Path $SRC $f) -Destination (Join-Path $DEST $f) -Force
  Say "✓ copied   ~\.claude\$f"
}

# 2) record where this checkout lives so the updater can `git pull` it
$parent = Split-Path -Parent $SRC
$repoRoot = if ($parent -and (Test-Path -LiteralPath (Join-Path $parent 'statusline-command.sh'))) { $parent } else { $SRC }
[System.IO.File]::WriteAllText((Join-Path $DEST 'statusline.repo'), $repoRoot)
Say "✓ recorded repo location for updates ($repoRoot)"

# 3) /mode command, generated with absolute paths (no symlinks on Windows).
#    Keep this text in step with ../mode.md (a wording port: ~\ paths, statusline-mode.ps1, __MODECMD__).
$modeScript = Join-Path $DEST 'statusline-mode.ps1'
$modeCmd = "$engine -NoProfile -ExecutionPolicy Bypass -File `"$modeScript`""
$modeMd = @'
---
description: Switch the status line preset (mode) for THIS Claude session
---

Set the status line mode (preset) for the current session.

Context:
- Modes live in `~\.claude\statusline.modes` as `name|description|ON-keys` (`ALL` = everything, `NONE` = nothing);
  `~\.claude\statusline.picker` is the curated picker list (`slconfig` -> g).
- `statusline-mode.ps1` does every write. Subcommands: `<mode>`, `--picker`, `--list`, `--show`,
  `--clear` (also `clear` / `default` / `reset`), `--global <mode>`.
- It writes `~\.claude\statusline.sessions\<id>.conf` for the id in env var `CLAUDE_CODE_SESSION_ID`; the renderer
  prefers that over the global `~\.claude\statusline.conf` (managed by `slconfig`). The change shows on the next
  status line refresh.

Argument the user passed (may be empty): `$ARGUMENTS`

## Empty (or `list` / `pick`): the picker
Bare `/mode` means the picker: call `AskUserQuestion`; never print the modes as text.
1. `__MODECMD__ --picker` prints `name|description` lines: the curated modes minus the one this session is on,
   capped at 4 (AskUserQuestion's option limit).
2. Call `AskUserQuestion` with one question, header `Mode`, one option per line: `label` = the name,
   `description` = the description. If `--picker` prints nothing, fall back to `--list` and offer up to 4.
3. Run `__MODECMD__ "<chosen name>"` and confirm in one line.

## `clear` / `default` / `reset`
Run `__MODECMD__ --clear` and confirm the session follows the global default again.

## Otherwise (a mode name)
Run `__MODECMD__ "$ARGUMENTS"` and confirm in one line; on "Unknown mode", open the picker.

Gotchas:
- Never edit conf files directly. The renderer parses strict `KEY=0/1` lines: unknown keys are ignored and a
  missing key shows that element ON.
- Without `CLAUDE_CODE_SESSION_ID` (set inside Claude Code's shell tool, absent in a plain terminal or hook) the
  script writes the GLOBAL default instead and says so; read its confirmation line before reporting.
- Every write deletes session confs older than 7 days, so a week-old session loses its override on the next
  `/mode` from any session.
- `--picker` hides the effective mode (the global default's mode when this session has no override), so the
  `--list` fallback only fires when the modes file is empty or every curated mode equals the current one.
'@
$modeMd = $modeMd.Replace('__MODECMD__', $modeCmd)
[System.IO.File]::WriteAllText((Join-Path $DEST 'commands\mode.md'), $modeMd)
Say '✓ installed /mode command'

# 4) seed the mode presets so /mode works immediately. Never clobber an existing file.
$modesDst = Join-Path $DEST 'statusline.modes'
if (-not (Test-Path -LiteralPath $modesDst)) {
  $candidates = @((Join-Path $SRC 'statusline.modes.example'))
  if ($parent) { $candidates += (Join-Path $parent 'statusline.modes.example') }
  $example = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
  if ($example) {
    Copy-Item -LiteralPath $example -Destination $modesDst
    Say '✓ seeded default modes  ~\.claude\statusline.modes'
  }
}

# 5) status line in settings.json (back up, then set .statusLine — native JSON, no jq)
$settings = Join-Path $DEST 'settings.json'
if (-not (Test-Path -LiteralPath $settings)) { [System.IO.File]::WriteAllText($settings, '{}') }
Copy-Item -LiteralPath $settings -Destination "$settings.bak" -Force
$settingsRaw = Get-Content -LiteralPath $settings -Raw
if (-not $settingsRaw -or -not $settingsRaw.Trim()) { $settingsRaw = '{}' }
$json = $settingsRaw | ConvertFrom-Json
if ($null -eq $json) { $json = New-Object psobject }
$slValue = [pscustomobject]@{
  type    = 'command'
  command = "$engine -NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $DEST 'statusline-command.ps1')`""
}
if ($json.PSObject.Properties['statusLine']) { $json.statusLine = $slValue }
else { $json | Add-Member -MemberType NoteProperty -Name statusLine -Value $slValue }
[System.IO.File]::WriteAllText($settings, ($json | ConvertTo-Json -Depth 32))
Say '✓ set statusLine in ~\.claude\settings.json (backup: settings.json.bak)'

# 6) slconfig in the PowerShell profile(s) — Windows PowerShell always; pwsh's too if present
if (-not $SkipProfile) {
  $docs = [Environment]::GetFolderPath('MyDocuments')
  if (-not $docs) { $docs = Join-Path $HOME_DIR 'Documents' }
  $profiles = @((Join-Path $docs 'WindowsPowerShell\profile.ps1'))
  if (Get-Command pwsh -ErrorAction SilentlyContinue) { $profiles += (Join-Path $docs 'PowerShell\profile.ps1') }
  $block = @"

# claude-statusline configurator
function slconfig { & $engine -NoProfile -ExecutionPolicy Bypass -File "`$env:USERPROFILE\.claude\statusline-config.ps1" }
"@
  foreach ($prof in $profiles) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $prof) | Out-Null
    $cur = ''
    if (Test-Path -LiteralPath $prof) { $cur = Get-Content -LiteralPath $prof -Raw }
    if ($cur -notmatch 'function\s+slconfig') {
      Add-Content -LiteralPath $prof -Value $block
      Say "✓ added 'slconfig' to $prof"
    } else {
      Say "• 'slconfig' already in $prof"
    }
  }
}

if (-not $Quiet) {
  Write-Host ''
  Write-Host 'Done 🎉'
  Write-Host '  • Restart Claude Code (or start a new session) to see the status line.'
  Write-Host '  • Open a NEW PowerShell window (so the profile reloads), then:'
  Write-Host '  • Configure modes:    slconfig'
  Write-Host '  • Switch this session''s mode inside Claude:  /mode'
}
