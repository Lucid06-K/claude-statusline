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

# 3) /mode command — generated with absolute paths (no symlinks on Windows)
$modeScript = Join-Path $DEST 'statusline-mode.ps1'
$modeCmd = "$engine -NoProfile -ExecutionPolicy Bypass -File `"$modeScript`""
$modeMd = @'
---
description: Switch the status line preset (mode) for THIS Claude session
---

Set the status line **mode** (preset) for the current session.

Context:
- Modes are defined in `~\.claude\statusline.modes`.
- The current session id is in `$CLAUDE_CODE_SESSION_ID` (env var `CLAUDE_CODE_SESSION_ID`).
- `statusline-mode.ps1` resolves a mode and writes a per-session conf
  (`~\.claude\statusline.sessions\<id>.conf`) the status line reads for this session only.
- The global default is managed separately with `slconfig`.

Argument the user passed (may be empty): `$ARGUMENTS`

## If `$ARGUMENTS` is empty (or `list` / `pick`) → SHOW THE PICKER

**You MUST open an interactive picker using the `AskUserQuestion` tool. Do NOT print the
modes as a text list, and do NOT answer in prose — the whole point of bare `/mode` is the picker.**

1. Run `__MODECMD__ --picker` → it prints `name|description` lines
   (the user's curated modes, current one already excluded, capped at 4).
2. Run `__MODECMD__ --show` → note the current mode (context only).
3. **Call `AskUserQuestion`** with a single question, header `Mode`, and **one option per
   `--picker` line**: `label` = the name, `description` = the description, and `preview` =
   a short plain-text sketch of that mode's status line. (If `--picker` returns nothing,
   fall back to `__MODECMD__ --list` and offer up to 4 modes.)
4. After the user picks, run `__MODECMD__ "<chosen name>"` and confirm
   in one short line.

## If `$ARGUMENTS` is `clear` / `default` / `reset`

Run `__MODECMD__ --clear` and confirm the session reverts to the global default.

## Otherwise (a mode name was given)

Run `__MODECMD__ "$ARGUMENTS"`. On success confirm in one line; if it
reports "Unknown mode", call `AskUserQuestion` with the available modes so they can pick.

Never edit files directly — always go through `statusline-mode.ps1`.
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
