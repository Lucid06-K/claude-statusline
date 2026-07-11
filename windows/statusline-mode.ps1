# Apply / inspect status-line modes — Windows (PowerShell) port of statusline-mode.sh.
# Per-session by default (uses $env:CLAUDE_CODE_SESSION_ID), so each Claude Code
# session can show a different preset. Driven by the /mode slash command.
#
#   statusline-mode.ps1 <mode>           apply <mode> to THIS session (or global if no session)
#   statusline-mode.ps1 --global <mode>  apply <mode> to the global default (all sessions)
#   statusline-mode.ps1 --list           list available modes
#   statusline-mode.ps1 --picker         name|description lines for the /mode picker
#   statusline-mode.ps1 --show           show the effective mode for this session
#   statusline-mode.ps1 --clear          drop this session's override (revert to global)

$ErrorActionPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$HOME_DIR = $env:USERPROFILE
if (-not $HOME_DIR) { $HOME_DIR = [Environment]::GetFolderPath('UserProfile') }
$CLAUDE  = Join-Path $HOME_DIR '.claude'
$MODES   = Join-Path $CLAUDE 'statusline.modes'
$GLOBAL  = Join-Path $CLAUDE 'statusline.conf'
$SESSDIR = Join-Path $CLAUDE 'statusline.sessions'
$PICKER  = Join-Path $CLAUDE 'statusline.picker'   # modes chosen (in slconfig) to show in /mode
$KEYS = @('SL_DIRECTORY','SL_GIT','SL_MODEL','SL_FASTMODE','SL_EFFORT','SL_CONTEXT','SL_CONTEXT_WARN',
          'SL_RATELIMIT_5H','SL_RATELIMIT_7D','SL_BURNRATE','SL_COST','SL_COST_COLOR','SL_ELAPSED',
          'SL_CLOCK','SL_OUTPUTSTYLE','SL_TOKENS','SL_THINKING')
$sid = $env:CLAUDE_CODE_SESSION_ID
if ($sid) { $sid = $sid -replace '[^\w\.\-]', '' }

function Get-SlModes {
  $out = @()
  if (Test-Path -LiteralPath $MODES) {
    foreach ($line in [System.IO.File]::ReadAllLines($MODES)) {
      $t = $line.Trim()
      if (-not $t -or $t.StartsWith('#')) { continue }
      $f = $line -split '\|', 3
      if ($f.Count -ge 2) {
        $out += [pscustomobject]@{
          name = $f[0].Replace(' ', '')
          desc = $f[1].Trim()
          spec = $(if ($f.Count -ge 3) { $f[2] } else { '' })
        }
      }
    }
  }
  $out
}
# Write-Host (not pipeline output) so these can be printed from inside functions
# that return a boolean — pipeline strings would be swallowed into the return value.
function Show-SlModes { foreach ($m in Get-SlModes) { Write-Host ('  {0,-10} {1}' -f $m.name, $m.desc) } }

# names of modes to surface in the /mode picker (slconfig's selection, in modes-file
# order; falls back to the first 4 modes if nothing has been chosen yet)
function Get-PickerNames {
  $modes = @(Get-SlModes)
  if ((Test-Path -LiteralPath $PICKER) -and (Get-Item -LiteralPath $PICKER).Length -gt 0) {
    $want = @{}
    foreach ($line in [System.IO.File]::ReadAllLines($PICKER)) { if ($line.Trim()) { $want[$line.Trim()] = 1 } }
    foreach ($m in $modes) { if ($want.ContainsKey($m.name)) { $m.name } }
  } else {
    $modes | Select-Object -First 4 | ForEach-Object { $_.name }
  }
}
function Get-SessConf { Join-Path $SESSDIR "$sid.conf" }
function Get-EffectiveConf { if ($sid -and (Test-Path -LiteralPath (Get-SessConf))) { Get-SessConf } else { $GLOBAL } }
function Get-CurrentMode {
  $c = Get-EffectiveConf
  if (Test-Path -LiteralPath $c) {
    foreach ($line in [System.IO.File]::ReadAllLines($c)) {
      if ($line.StartsWith('SL_MODE=')) { return $line.Substring(8) }
    }
  }
  ''
}
function Write-SlConf([string]$mode, [string]$target) {
  $m = @(Get-SlModes) | Where-Object { $_.name -eq $mode } | Select-Object -First 1
  if (-not $m) { Write-Host "Unknown mode: '$mode'. Available:"; Show-SlModes; return $false }
  $on = @()
  switch ($m.spec.Trim()) {
    'ALL'   { $on = $KEYS }
    'NONE'  { $on = @() }
    default { $on = @($m.spec -split '\s+' | Where-Object { $_ }) }
  }
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine('# status line conf — managed by /mode')
  [void]$sb.AppendLine("SL_MODE=$mode")
  foreach ($k in $KEYS) { [void]$sb.AppendLine("$k=$(if ($on -contains $k) { 1 } else { 0 })") }
  [System.IO.File]::WriteAllText($target, $sb.ToString())
  if (Test-Path -LiteralPath $SESSDIR) {   # prune stale per-session confs
    Get-ChildItem -LiteralPath $SESSDIR -Filter '*.conf' | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } | Remove-Item -Force
  }
  $true
}

$a1 = if ($args.Count -ge 1) { [string]$args[0] } else { '' }
$a2 = if ($args.Count -ge 2) { [string]$args[1] } else { '' }

switch ($a1) {
  { $_ -in '', '--list', 'list' } {
    'Available modes:'; Show-SlModes
    $m = Get-CurrentMode
    ''; "This session: $(if ($m) { $m } else { 'custom' })"
    break
  }
  '--picker' {
    # name|description for the picker: curated modes, minus the one this session is
    # already on (switching to it is a no-op), capped at 4 (AskUserQuestion's limit).
    # NB: named $allModes, NOT $modes — PS variables are case-insensitive, and at
    # script scope $modes would clobber the $MODES path.
    $cur = Get-CurrentMode
    $allModes = @(Get-SlModes)
    $count = 0
    foreach ($nm in @(Get-PickerNames)) {
      if (-not $nm -or $nm -eq $cur) { continue }
      if ($count -ge 4) { break }
      $mm = $allModes | Where-Object { $_.name -eq $nm } | Select-Object -First 1
      '{0}|{1}' -f $nm, $mm.desc
      $count++
    }
    break
  }
  { $_ -in '--show', 'show' } {
    $m = Get-CurrentMode
    if (-not $m) { $m = '(custom)' }
    if ($sid -and (Test-Path -LiteralPath (Get-SessConf))) { "This session: $m  (per-session)" }
    else { "This session: $m  (global default)" }
    break
  }
  { $_ -in '--clear', 'clear', 'default', 'reset' } {
    if ($sid -and (Test-Path -LiteralPath (Get-SessConf))) {
      Remove-Item -LiteralPath (Get-SessConf) -Force
      'Reverted this session to the global default.'
    } else {
      'This session already follows the global default.'
    }
    break
  }
  { $_ -in '--global', '-g' } {
    if (-not $a2) { 'Usage: --global <mode>'; exit 1 }
    if (Write-SlConf $a2 $GLOBAL) { "Global default set to '$a2' (affects sessions without their own mode)." }
    break
  }
  default {
    if ($sid) {
      if (Write-SlConf $a1 (Get-SessConf)) { "This session is now using '$a1' (applies on the next status line refresh)." }
    } else {
      if (Write-SlConf $a1 $GLOBAL) { "No session id detected — set the global default to '$a1'." }
    }
  }
}
