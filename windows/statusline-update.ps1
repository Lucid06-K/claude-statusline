# Update claude-statusline — Windows (PowerShell) port of statusline-update.sh.
# On Windows the scripts are COPIES (symlinks need admin), so the installer records
# the repo path in ~/.claude/statusline.repo; updating = fast-forward `git pull` of
# that repo, then re-running the installer wiring (which re-copies the scripts).
# Pinned to the repo's HTTPS origin, never elevated.
#
#   statusline-update.ps1                check + update to the latest (interactive output)
#   statusline-update.ps1 --check        quiet: exit 0 = up to date, 10 = behind, 1 = can't tell
#   statusline-update.ps1 --background   used by the daily auto-check (silent; pulls if behind)
#   statusline-update.ps1 --auto on|off  enable/disable the once-a-day background auto-update
#   statusline-update.ps1 --status       print version + auto-update state

$ErrorActionPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$HOME_DIR = $env:USERPROFILE
if (-not $HOME_DIR) { $HOME_DIR = [Environment]::GetFolderPath('UserProfile') }
$CLAUDE   = Join-Path $HOME_DIR '.claude'
$REPOFILE = Join-Path $CLAUDE 'statusline.repo'          # written by install.ps1
$AUTOFLAG = Join-Path $CLAUDE 'statusline.auto-update'   # presence = auto-update enabled

$REPO = ''
if (Test-Path -LiteralPath $REPOFILE) { $REPO = ([System.IO.File]::ReadAllText($REPOFILE)).Trim() }

function Test-IsGit {
  if (-not $REPO -or -not (Test-Path -LiteralPath $REPO)) { return $false }
  if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return $false }
  git -C $REPO rev-parse --git-dir 2>$null | Out-Null
  $LASTEXITCODE -eq 0
}
function Get-CurVer {
  $vf = Join-Path $REPO 'VERSION'
  if ($REPO -and (Test-Path -LiteralPath $vf)) { ([System.IO.File]::ReadAllText($vf)).Trim() } else { '?' }
}
function Get-CurRev { (git -C $REPO log -1 --format='%h %cd' --date=short 2>$null) -join '' }

function Get-BehindCount {   # commits behind origin's default branch; $null = offline
  $br = (git -C $REPO rev-parse --abbrev-ref HEAD 2>$null) -join ''
  if (-not $br) { $br = 'main' }
  git -C $REPO fetch --quiet origin 2>$null | Out-Null
  if ($LASTEXITCODE -ne 0) { return $null }
  $n = (git -C $REPO rev-list --count "HEAD..origin/$br" 2>$null) -join ''
  if ($LASTEXITCODE -ne 0 -or -not $n) { return 0 }
  [int]$n
}

function Invoke-Apply {   # fast-forward pull, syntax-check, then re-run installer wiring
  $br = (git -C $REPO rev-parse --abbrev-ref HEAD 2>$null) -join ''
  if (-not $br) { $br = 'main' }
  git -C $REPO pull --ff-only --quiet origin $br 2>$null | Out-Null
  if ($LASTEXITCODE -ne 0) {
    # Write-Host, not pipeline output — pipeline strings would be swallowed into
    # the boolean this function returns.
    Write-Host "  ✗ pull failed — you may have local changes. Check: git -C `"$REPO`" status"
    return $false
  }
  foreach ($f in 'statusline-command.ps1', 'statusline-config.ps1', 'statusline-mode.ps1', 'statusline-update.ps1', 'install.ps1') {
    $p = Join-Path $REPO "windows\$f"
    if (Test-Path -LiteralPath $p) {
      $toks = $null; $errs = $null
      [void][System.Management.Automation.Language.Parser]::ParseFile($p, [ref]$toks, [ref]$errs)
      if ($errs -and $errs.Count) { Write-Host "  ✗ syntax error in windows\$f after update (not loaded)"; return $false }
    }
  }
  # Self-heal: re-run the installer wiring so updates propagate (re-copies scripts,
  # refreshes the /mode command and settings; -SkipProfile leaves your profile alone).
  $inst = Join-Path $REPO 'windows\install.ps1'
  if (Test-Path -LiteralPath $inst) {
    $me = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    & $me -NoProfile -ExecutionPolicy Bypass -File $inst -Quiet -SkipProfile | Out-Null
  }
  $true
}

$a1 = if ($args.Count -ge 1) { [string]$args[0] } else { '' }
$a2 = if ($args.Count -ge 2) { [string]$args[1] } else { '' }

switch ($a1) {
  '--check' {
    if (-not (Test-IsGit)) { 'not a git checkout'; exit 1 }
    $n = Get-BehindCount
    if ($null -eq $n) { 'offline'; exit 1 }
    if ($n -gt 0) { "$n update(s) available"; exit 10 } else { 'up to date'; exit 0 }
  }
  '--background' {   # daily auto-check (already throttled by the caller)
    if (-not (Test-Path -LiteralPath $AUTOFLAG)) { exit 0 }
    if (-not (Test-IsGit)) { exit 0 }
    $n = Get-BehindCount
    if ($null -ne $n -and $n -gt 0) { Invoke-Apply | Out-Null }
    exit 0
  }
  '--auto' {
    switch ($a2) {
      'on'  { [System.IO.File]::WriteAllText($AUTOFLAG, ''); 'Auto-update ON — checks once a day in the background.' }
      'off' { Remove-Item -LiteralPath $AUTOFLAG -Force -ErrorAction SilentlyContinue; 'Auto-update OFF.' }
      default { if (Test-Path -LiteralPath $AUTOFLAG) { 'Auto-update is ON' } else { 'Auto-update is OFF' } }
    }
  }
  '--status' {
    if (Test-IsGit) { "claude-statusline $(Get-CurVer) — $(Get-CurRev)" } else { "claude-statusline $(Get-CurVer) (not a git checkout)" }
    if (Test-Path -LiteralPath $AUTOFLAG) { 'auto-update: on' } else { 'auto-update: off' }
  }
  default {
    if (-not (Test-IsGit)) { 'Not a git checkout. Reinstall from https://github.com/Lucid06-K/claude-statusline'; exit 1 }
    "Checking for updates…  (current: $(Get-CurVer), $(Get-CurRev))"
    $n = Get-BehindCount
    if ($null -eq $n) { "Couldn't reach GitHub — offline?"; exit 1 }
    if ($n -eq 0) { 'Already up to date.'; exit 0 }
    "$n new commit(s) available. Updating…"
    if (Invoke-Apply) { "✓ Updated to $(Get-CurVer) ($(Get-CurRev)). Restart Claude Code to load it." } else { exit 1 }
  }
}
