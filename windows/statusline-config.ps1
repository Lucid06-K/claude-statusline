# Mode manager for the Claude Code status line — Windows (PowerShell) port of
# statusline-config.sh (arrow-key TUI, dsort layout).
# - Main screen lists MODES (presets). Enter sets the highlighted mode as the
#   DEFAULT for new sessions (writes ~/.claude/statusline.conf).
# - e = edit / c = create opens the element editor (individual on/off lives there).
# - Per-session selection happens inside Claude with the /mode command.
# - Modes are stored in ~/.claude/statusline.modes (managed here, no file editing).
# Works on Windows PowerShell 5.1 and pwsh 7+ (Windows Terminal or conhost).

param([switch]$NoMenu)   # -NoMenu: draw the main screen once and exit (smoke test)

$ErrorActionPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

# Enable ANSI (VT) processing on legacy conhost — Windows Terminal and pwsh 7+
# already have it on; Windows PowerShell 5.1 in a bare console does not.
if (-not $env:WT_SESSION -and $PSVersionTable.PSVersion.Major -lt 7) {
  try {
    Add-Type -Namespace CcSl -Name Vt -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError=true)] public static extern IntPtr GetStdHandle(int n);
[DllImport("kernel32.dll", SetLastError=true)] public static extern bool GetConsoleMode(IntPtr h, out uint m);
[DllImport("kernel32.dll", SetLastError=true)] public static extern bool SetConsoleMode(IntPtr h, uint m);
'@
    $h = [CcSl.Vt]::GetStdHandle(-11); $m = 0
    if ([CcSl.Vt]::GetConsoleMode($h, [ref]$m)) { [void][CcSl.Vt]::SetConsoleMode($h, $m -bor 4) }
  } catch {}
}

$HOME_DIR = $env:USERPROFILE
if (-not $HOME_DIR) { $HOME_DIR = [Environment]::GetFolderPath('UserProfile') }
$CLAUDE = Join-Path $HOME_DIR '.claude'
$CONF   = Join-Path $CLAUDE 'statusline.conf'
$MODES  = Join-Path $CLAUDE 'statusline.modes'
# NB: PS variable names are case-insensitive — this must NOT be called $PICKER,
# or the $script:Picker state array below would clobber it.
$PICKERFILE = Join-Path $CLAUDE 'statusline.picker'
$ENGINE = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName

# installed copies first; fall back to siblings so the repo checkout works pre-install
$SLSCRIPT = Join-Path $CLAUDE 'statusline-command.ps1'
if (-not (Test-Path -LiteralPath $SLSCRIPT)) { $SLSCRIPT = Join-Path $PSScriptRoot 'statusline-command.ps1' }
$UPDATE = Join-Path $CLAUDE 'statusline-update.ps1'
if (-not (Test-Path -LiteralPath $UPDATE)) { $UPDATE = Join-Path $PSScriptRoot 'statusline-update.ps1' }

$E = [char]27
$R = "$E[0m"; $B = "$E[1m"; $DIM = "$E[2m"; $REV = "$E[7m"
$GRN = "$E[92m"; $YEL = "$E[93m"; $CYN = "$E[96m"; $MAG = "$E[95m"; $RED = "$E[91m"
$ORANGE = "$E[38;2;215;119;87m"
$SEP = "$DIM──────────────────────────────────────────────────────────$R"

# mini coloured bar (matches the status line's mk_bar) — used by the per-element previews
function Get-MiniBar([int]$pct, [int]$width = 6) {
  $filled = [int][Math]::Floor(($pct * $width + 50) / 100)
  if ($filled -gt $width) { $filled = $width }
  if ($filled -lt 0) { $filled = 0 }
  $empty = $width - $filled
  $col = if ($pct -ge 80) { 91 } elseif ($pct -ge 50) { 93 } else { 92 }
  "$E[90m▕$E[${col}m$('█' * $filled)$E[90m$('░' * $empty)▏$R"
}

# key | label | one-line summary | full explanation
$KEYS = @('SL_DIRECTORY','SL_GIT','SL_MODEL','SL_FASTMODE','SL_EFFORT','SL_CONTEXT','SL_CONTEXT_WARN',
          'SL_RATELIMIT_5H','SL_RATELIMIT_7D','SL_BURNRATE','SL_COST','SL_COST_COLOR','SL_ELAPSED',
          'SL_CLOCK','SL_OUTPUTSTYLE','SL_TOKENS','SL_THINKING')
$LABELS = @('Directory','Git status','Model name','Fast-mode flag','Reasoning effort',
            'Context meter','Context warning','5-hour limit','7-day limit','Burn rate',
            'Session cost','Cost color','Session timer','Clock',
            'Output style','Tokens','Thinking off')
$SHORTS = @('current folder (📁 ~\…)',
            'branch, dirty *, ahead/behind ⇡⇣',
            'model name in Claude orange',
            '⚡ when /fast is on',
            'reasoning effort, colored like the selector',
            'context-window bar + %',
            '⚠ when context is near auto-compact',
            'rolling 5-hour usage meter',
            'weekly allowance meter (rolling 7 days)',
            'spend rate, $ per active hour',
            'total $ spent this session',
            'tint the $ as spend climbs',
            '⏱ time since session start',
            'current time of day',
            '✎ active output style (not default)',
            '↓in ↑out tokens this session',
            '🧠⨯ when extended thinking is off')
$LONGS = @('The working directory. Home shows as ~, a folder directly under home as ~\name, and anything deeper as the last two path segments (e.g. Projects\poyona).',
           'When inside a git repo: the branch, a * if there are uncommitted changes, and ⇡N/⇣N for commits ahead of / behind upstream. Hidden outside repos; turning it off also skips the git calls (slightly faster).',
           "The active model's display name (e.g. Opus 4.8 (1M context)) in Claude's brand orange.",
           'A ⚡ next to the model only while fast mode (/fast) is active.',
           "Your reasoning-effort level (low/medium/high/xhigh/max), colored to match Claude Code's own effort selector: yellow / green / blue / magenta / rainbow.",
           'A 6-cell bar + percentage of how full the context window is, shifting green → yellow → red as it fills.',
           "A red ⚠ on the context meter once usage passes 85% — i.e. you're close to an automatic /compact.",
           "How much of your plan's rolling 5-hour allowance is spent (bar + %). At ≥80% it shows a ⟳ reset countdown. Hitting 100% is what triggers 'Now using usage credits'.",
           'Your weekly allowance: the same meter for the rolling 7-day window, always shown once Claude Code has sent a reading. Reset countdown at ≥80%.',
           'Spend velocity: dollars per hour of active processing time (cost ÷ active duration).',
           'Total dollars spent in this session so far.',
           'Tints the cost figure with spend: dim under $2, yellow at ≥$2, red at ≥$5. Off = plain text.',
           'A ⏱ timer counting wall-clock time since the session began (via a small marker file, auto-cleaned after 2 days).',
           'The current clock time (HH:MM).',
           'The active output style (e.g. Explanatory, Learning) shown with a ✎. Hidden when it''s the default style.',
           'Tokens used this session — ↓ total input and ↑ total output, abbreviated (k/M).',
           "A 🧠⨯ shown only when extended thinking is turned off (it's normally on).")
$N = $KEYS.Count

$script:TmpState = @(0) * $N
$script:ED = @(0) * $N
$script:CurrentMode = ''
$script:EDNAME = ''
$script:EDDESC = ''
$script:ModeNames = @(); $script:ModeDescs = @(); $script:ModeSpecs = @()
$script:Picker = @()

# Per-element example renders — shown for whichever option the editor selector sits on.
$PREV = @(
  '📁 Projects\poyona',
  "feat/vet $GRN⇡2$R",
  "${ORANGE}Opus 4.8$R",
  "${ORANGE}Opus 4.8$R $YEL⚡$R",
  "${MAG}xhigh$R",
  "$DIM»«$R$(Get-MiniBar 42 6) 42%",
  "$DIM»«$R$(Get-MiniBar 88 6) 88% $RED⚠$R",
  "5h $(Get-MiniBar 83 6) 83% $DIM⟳ 2h35m$R",
  "7d $(Get-MiniBar 72 6) 72%",
  '$11.20/h',
  '$6.40',
  ($RED + '$6.40' + $R),
  '⏱ 12m',
  '19:02',
  "$CYN✎ Explanatory$R",
  "$DIM↓${R}37k $DIM↑${R}264",
  "$YEL🧠⨯$R"
)

# ---------- one keypress -> token ----------
function Read-Key {
  while ($true) {
    $k = [Console]::ReadKey($true)
    if (($k.Modifiers -band [ConsoleModifiers]::Control) -and $k.Key -eq [ConsoleKey]::C) { return 'ctrlc' }
    switch ($k.Key) {
      ([ConsoleKey]::UpArrow)   { return 'up' }
      ([ConsoleKey]::DownArrow) { return 'down' }
      ([ConsoleKey]::Escape)    { return 'esc' }
      ([ConsoleKey]::Enter)     { return 'enter' }
      ([ConsoleKey]::Spacebar)  { return 'space' }
      default { if ($k.KeyChar) { return [string]$k.KeyChar } }
      # anything else (←/→, Home, End, PgUp, F-keys) is ignored — a stray arrow
      # must not quit and discard in-progress edits
    }
  }
}
function Wait-AnyKey {
  [Console]::Write("`n  ${DIM}press any key$R")
  [void][Console]::ReadKey($true)
}
function Write-Frame([System.Text.StringBuilder]$sb) { [Console]::Write($sb.ToString()) }
function New-Frame {
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append("$E[H$E[2J")
  , $sb
}

# ---------- global default (the conf the status line reads for new sessions) ----------
function Read-DefaultMode {
  $script:CurrentMode = ''
  if (-not (Test-Path -LiteralPath $CONF)) { return }
  foreach ($line in [System.IO.File]::ReadAllLines($CONF)) {
    if ($line.StartsWith('SL_MODE=')) { $script:CurrentMode = $line.Substring(8); return }
  }
}
function Write-Default([string]$name) {   # uses $script:TmpState
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine('# Claude Code status line — global default for new sessions (managed by slconfig)')
  [void]$sb.AppendLine("SL_MODE=$name")
  for ($i = 0; $i -lt $N; $i++) { [void]$sb.AppendLine("$($KEYS[$i])=$($script:TmpState[$i])") }
  [System.IO.File]::WriteAllText($CONF, $sb.ToString())
  $script:CurrentMode = $name
}

# ---------- modes ----------
function Initialize-Modes {
  if (Test-Path -LiteralPath $MODES) { return }
  New-Item -ItemType Directory -Force -Path $CLAUDE | Out-Null
  $seed = @(
    '# Claude Code status line — modes (presets). Managed via the configurator menu.'
    '# format:  name|description|ON-keys (space separated; ALL = everything, NONE = nothing)'
    'full|Everything on|ALL'
    'work|Coding essentials — path, git, model, effort, context|SL_DIRECTORY SL_GIT SL_MODEL SL_FASTMODE SL_EFFORT SL_CONTEXT SL_CONTEXT_WARN SL_CLOCK'
    'cost|Watch spend & rate limits|SL_DIRECTORY SL_MODEL SL_RATELIMIT_5H SL_RATELIMIT_7D SL_BURNRATE SL_COST SL_COST_COLOR SL_CLOCK'
    'minimal|Path, git, model, clock|SL_DIRECTORY SL_GIT SL_MODEL SL_CLOCK'
    'focus|Just enough to stay oriented|SL_DIRECTORY SL_MODEL SL_EFFORT'
    'zen|Nothing — a clean, empty line|NONE'
  )
  [System.IO.File]::WriteAllText($MODES, ($seed -join "`n") + "`n")
}
function Read-Modes {
  $script:ModeNames = @(); $script:ModeDescs = @(); $script:ModeSpecs = @()
  if (-not (Test-Path -LiteralPath $MODES)) { return }
  foreach ($line in [System.IO.File]::ReadAllLines($MODES)) {
    $t = $line.Trim()
    if (-not $t -or $t.StartsWith('#')) { continue }
    $f = $line -split '\|', 3
    if ($f.Count -lt 2) { continue }
    $script:ModeNames += $f[0].Replace(' ', '')
    $script:ModeDescs += $f[1].Trim()
    $script:ModeSpecs += $(if ($f.Count -ge 3) { $f[2] } else { '' })
  }
}
function Convert-SpecToState([string]$spec) {   # fill $script:TmpState from a spec string
  for ($i = 0; $i -lt $N; $i++) { $script:TmpState[$i] = 0 }
  $words = @("$spec" -split '\s+' | Where-Object { $_ })
  if ($words.Count -eq 0) { return }
  if ($words[0] -ceq 'ALL') { for ($i = 0; $i -lt $N; $i++) { $script:TmpState[$i] = 1 }; return }
  if ($words[0] -ceq 'NONE') { return }
  foreach ($w in $words) {
    for ($i = 0; $i -lt $N; $i++) { if ($KEYS[$i] -eq $w) { $script:TmpState[$i] = 1 } }
  }
}
function Convert-SpecToConf([string]$spec) {   # -> KEY=0/1 lines
  Convert-SpecToState $spec
  $lines = @()
  for ($i = 0; $i -lt $N; $i++) { $lines += "$($KEYS[$i])=$($script:TmpState[$i])" }
  $lines
}
function Convert-EdToSpec {
  $on = @(); $allon = $true; $alloff = $true
  for ($i = 0; $i -lt $N; $i++) {
    if ($script:ED[$i] -eq 1) { $on += $KEYS[$i]; $alloff = $false } else { $allon = $false }
  }
  if ($allon) { 'ALL' } elseif ($alloff) { 'NONE' } else { $on -join ' ' }
}
# Remove a mode by EXACT first-field match (a name used as a regex could drop
# unrelated lines, or wipe the whole file for a name like ".*").
function Remove-ModeLine([string]$name) {
  Initialize-Modes
  $keep = @()
  foreach ($line in [System.IO.File]::ReadAllLines($MODES)) {
    $first = ($line -split '\|', 2)[0]
    if ($first -ne $name) { $keep += $line }
  }
  if ($keep.Count -gt 0) { [System.IO.File]::WriteAllText($MODES, ($keep -join "`n") + "`n") }
}
function Save-Mode([string]$name, [string]$desc, [string]$spec) {
  # strip the '|' field delimiter (and a leading '#', which Read-Modes treats as a
  # comment) from the name/description so they can't corrupt the modes file
  $nm = $name.Replace('|', ''); $ds = $desc.Replace('|', '')
  $nm = $nm.TrimStart('#')
  Remove-ModeLine $nm
  [System.IO.File]::AppendAllText($MODES, ('{0}|{1}|{2}' -f $nm, $ds, $spec) + "`n")
  Read-Modes
}
function Set-DefaultByIndex([int]$i) {
  Convert-SpecToState $script:ModeSpecs[$i]
  Write-Default $script:ModeNames[$i]
}
function Remove-ModeByIndex([int]$i) {
  $nm = $script:ModeNames[$i]
  Remove-ModeLine $nm
  if ($script:CurrentMode -eq $nm) {
    $script:CurrentMode = ''
    # the deleted mode was the global default — clear SL_MODE in the conf too, or the
    # header keeps naming a mode that no longer exists (re-read every frame)
    if (Test-Path -LiteralPath $CONF) {
      $out = @()
      foreach ($line in [System.IO.File]::ReadAllLines($CONF)) {
        if ($line.StartsWith('SL_MODE=')) { $out += 'SL_MODE=' } else { $out += $line }
      }
      [System.IO.File]::WriteAllText($CONF, ($out -join "`n") + "`n")
    }
  }
  $script:Picker = @($script:Picker | Where-Object { $_ -ne $nm })
  Save-Picker
  Read-Modes
}

# ---------- /mode picker selection (which modes appear in the in-Claude /mode picker) ----------
function Read-Picker {
  $script:Picker = @()
  if (Test-Path -LiteralPath $PICKERFILE) {
    foreach ($line in [System.IO.File]::ReadAllLines($PICKERFILE)) { if ($line.Trim()) { $script:Picker += $line.Trim() } }
  } else {
    for ($i = 0; $i -lt $script:ModeNames.Count -and $i -lt 5; $i++) { $script:Picker += $script:ModeNames[$i] }
    Save-Picker
  }
}
function Test-InPicker([string]$name) { $script:Picker -contains $name }
function Save-Picker {
  $txt = ''
  foreach ($x in $script:Picker) { $txt += "$x`n" }
  [System.IO.File]::WriteAllText($PICKERFILE, $txt)
}
function Switch-Picker([string]$name) {   # $false if blocked by the 5-item cap
  if (Test-InPicker $name) {
    $script:Picker = @($script:Picker | Where-Object { $_ -ne $name })
    Save-Picker
    return $true
  }
  if ($script:Picker.Count -ge 5) { return $false }
  $script:Picker += $name
  Save-Picker
  $true
}

# ---------- preview ----------
function Invoke-RenderSample([string]$confPath) {   # runs the renderer in-process on sample
  $r5 = [System.DateTimeOffset]::Now.ToUnixTimeSeconds() + 2820   # data, isolated so it never
  $td = Join-Path $env:TEMP "cc-sl-preview-$PID"                  # touches the real caches
  New-Item -ItemType Directory -Force -Path $td | Out-Null
  $sample = @{
    session_id = "preview-$PID"
    cwd = $HOME_DIR
    effort = @{ level = 'xhigh' }
    model = @{ display_name = 'Opus 4.8 (1M context)' }
    workspace = @{ current_dir = $HOME_DIR }
    context_window = @{ used_percentage = 88 }
    fast_mode = $true
    cost = @{ total_cost_usd = 6.40; total_duration_ms = 720000 }
    rate_limits = @{
      five_hour = @{ used_percentage = 100; resets_at = $r5 }
      seven_day = @{ used_percentage = 72; resets_at = $r5 }
    }
  }
  $json = $sample | ConvertTo-Json -Depth 8
  $oldConf = $env:SL_CONF; $oldTmp = $env:CC_SL_TMP; $oldInproc = $env:CC_SL_INPROC; $oldCt = $env:COLORTERM
  try {
    if ($confPath) { $env:SL_CONF = $confPath } else { $env:SL_CONF = $null }
    $env:CC_SL_TMP = $td
    $env:CC_SL_INPROC = '1'
    if (-not $env:COLORTERM) { $env:COLORTERM = 'truecolor' }
    $out = @($json | & $SLSCRIPT) -join ''
  } finally {
    $env:SL_CONF = $oldConf; $env:CC_SL_TMP = $oldTmp; $env:CC_SL_INPROC = $oldInproc; $env:COLORTERM = $oldCt
    Remove-Item -Recurse -Force -LiteralPath $td -ErrorAction SilentlyContinue
  }
  $out
}
function Show-Preview([string]$confPath) {
  [Console]::Write("`n  ${B}Preview$R $DIM(sample data: busy session)$R`n  ")
  [Console]::Write((Invoke-RenderSample $confPath))
  [Console]::Write("`n")
}
function Get-SpecPreview([string]$spec) {
  $tc = [System.IO.Path]::GetTempFileName()
  [System.IO.File]::WriteAllText($tc, ((Convert-SpecToConf $spec) -join "`n") + "`n")
  $out = Invoke-RenderSample $tc
  Remove-Item -LiteralPath $tc -Force -ErrorAction SilentlyContinue
  $out
}

# ---------- row renderers (dsort style: ▸ + reverse-video on focus) ----------
function Get-RowToggle([int]$i, [int]$on, [bool]$foc) {
  $chk = if ($on -eq 1) { '✓' } else { ' ' }
  if ($foc) { "  $REV ▸ [$chk] $($LABELS[$i].PadRight(16)) $($SHORTS[$i]) $R" }
  else {
    $g = if ($on -eq 1) { "$GRN✓$R" } else { ' ' }
    "     [$g] $($LABELS[$i].PadRight(16)) $DIM$($SHORTS[$i])$R"
  }
}
function Get-RowAction([string]$text, [bool]$foc) {
  if ($foc) { "  $REV ▸ $text $R" } else { "     $text" }
}

# ---------- prompts (line input with a visible cursor) ----------
function Read-Line([string]$prompt) {
  [Console]::CursorVisible = $true
  $v = Read-Host "  $prompt"
  [Console]::CursorVisible = $false
  $v
}

# ---------- mode editor (where individual on/off lives) ----------
function Edit-SlMode($idx) {   # $idx = index to edit, or $null to create new
  $oldname = ''
  if ($null -ne $idx) {
    $script:EDNAME = $script:ModeNames[$idx]; $script:EDDESC = $script:ModeDescs[$idx]; $oldname = $script:EDNAME
    Convert-SpecToState $script:ModeSpecs[$idx]
  } else {
    $script:EDNAME = ''; $script:EDDESC = ''
    for ($i = 0; $i -lt $N; $i++) { $script:TmpState[$i] = 0 }
  }
  for ($i = 0; $i -lt $N; $i++) { $script:ED[$i] = $script:TmpState[$i] }
  $focus = 0
  $nrows = $N + 4   # elements + Rename / Description / Save / Cancel
  while ($true) {
    $sb = New-Frame
    $title = if ($oldname) { 'Edit mode' } else { 'New mode' }
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("  $B$title$R  $DIM— toggle what this mode includes$R")
    $nmDisp = if ($script:EDNAME) { $script:EDNAME } else { '<unset>' }
    $dsDisp = if ($script:EDDESC) { $script:EDDESC } else { '<none>' }
    [void]$sb.AppendLine("  name $CYN$nmDisp$R   desc $DIM$dsDisp$R")
    [void]$sb.AppendLine("  $SEP")
    for ($i = 0; $i -lt $N; $i++) { [void]$sb.AppendLine((Get-RowToggle $i $script:ED[$i] ($focus -eq $i))) }
    [void]$sb.AppendLine("  $SEP")
    [void]$sb.AppendLine((Get-RowAction 'Rename' ($focus -eq $N)))
    [void]$sb.AppendLine((Get-RowAction 'Edit description' ($focus -eq ($N + 1))))
    [void]$sb.AppendLine((Get-RowAction "${GRN}Save mode$R" ($focus -eq ($N + 2))))
    [void]$sb.AppendLine((Get-RowAction 'Cancel' ($focus -eq ($N + 3))))
    if ($focus -lt $N) { $pv = $PREV[$focus] }
    else {
      $tc = [System.IO.Path]::GetTempFileName()
      $lines = @(); for ($i = 0; $i -lt $N; $i++) { $lines += "$($KEYS[$i])=$($script:ED[$i])" }
      [System.IO.File]::WriteAllText($tc, ($lines -join "`n") + "`n")
      $pv = Invoke-RenderSample $tc
      Remove-Item -LiteralPath $tc -Force -ErrorAction SilentlyContinue
    }
    [void]$sb.AppendLine("  $SEP")
    [void]$sb.AppendLine("  ${DIM}render$R  $pv")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("  $DIM↑/↓ move · enter toggle · ? explain · r rename · t desc · p preview · s save · esc cancel$R")
    Write-Frame $sb
    $key = Read-Key
    switch ($key) {
      'ctrlc' { Complete-Cleanup; exit 130 }
      'up'    { $focus = ($focus + $nrows - 1) % $nrows }
      'k'     { $focus = ($focus + $nrows - 1) % $nrows }
      'down'  { $focus = ($focus + 1) % $nrows }
      'j'     { $focus = ($focus + 1) % $nrows }
      'esc'   { return }
      '?'     {
        if ($focus -lt $N) {
          $sb2 = New-Frame
          [void]$sb2.AppendLine()
          [void]$sb2.AppendLine("  $B$($LABELS[$focus])$R — $DIM$($SHORTS[$focus])$R")
          [void]$sb2.AppendLine()
          [void]$sb2.AppendLine("  $($LONGS[$focus])")
          Write-Frame $sb2
          Wait-AnyKey
        }
      }
      'r'     { $v = (Read-Line 'Name (one word)') -replace '\s', ''; if ($v) { $script:EDNAME = $v } }
      't'     { $script:EDDESC = Read-Line 'Description' }
      'p'     {
        $tc = [System.IO.Path]::GetTempFileName()
        $lines = @(); for ($i = 0; $i -lt $N; $i++) { $lines += "$($KEYS[$i])=$($script:ED[$i])" }
        [System.IO.File]::WriteAllText($tc, ($lines -join "`n") + "`n")
        Show-Preview $tc
        Remove-Item -LiteralPath $tc -Force -ErrorAction SilentlyContinue
        Wait-AnyKey
      }
      's'     { if (Save-EditedMode $oldname) { return } }
      'enter' {
        if ($focus -lt $N) { $script:ED[$focus] = 1 - $script:ED[$focus] }
        elseif ($focus -eq $N) { $v = (Read-Line 'Name (one word)') -replace '\s', ''; if ($v) { $script:EDNAME = $v } }
        elseif ($focus -eq ($N + 1)) { $script:EDDESC = Read-Line 'Description' }
        elseif ($focus -eq ($N + 2)) { if (Save-EditedMode $oldname) { return } }
        else { return }
      }
    }
  }
}
function Save-EditedMode([string]$oldname) {   # $true to close the editor
  if (-not $script:EDNAME) { $script:EDNAME = (Read-Line 'Name this mode (one word)') -replace '\s', '' }
  if (-not $script:EDNAME) { [Console]::Write("`n  ${YEL}Name required.$R"); Wait-AnyKey; return $false }
  if ($oldname -and $oldname -ne $script:EDNAME) {
    Remove-ModeLine $oldname
    # a rename must follow into the /mode picker file too, or the renamed mode
    # vanishes from the picker and its old name lingers as a dead, unremovable entry
    if (Test-InPicker $oldname) {
      $script:Picker = @($script:Picker | ForEach-Object { if ($_ -eq $oldname) { $script:EDNAME } else { $_ } })
      Save-Picker
    }
  }
  Save-Mode $script:EDNAME $script:EDDESC (Convert-EdToSpec)
  if ($oldname -and $script:CurrentMode -eq $oldname) { $script:CurrentMode = $script:EDNAME }
  # if we edited the current default, refresh the global conf so it stays in sync
  if ($script:EDNAME -eq $script:CurrentMode) {
    for ($j = 0; $j -lt $script:ModeNames.Count; $j++) {
      if ($script:ModeNames[$j] -eq $script:EDNAME) { Set-DefaultByIndex $j; break }
    }
  }
  $true
}

# ---------- updates (git fast-forward via statusline-update.ps1) ----------
function Show-UpdateMenu {
  $focus = 0; $rows = 3; $msg = ''
  $autoFlag = Join-Path $CLAUDE 'statusline.auto-update'
  while ($true) {
    $auto = if (Test-Path -LiteralPath $autoFlag) { "${GRN}on$R" } else { 'off' }
    $status = (& $ENGINE -NoProfile -ExecutionPolicy Bypass -File $UPDATE --status 2>$null | Select-Object -First 1)
    $sb = New-Frame
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("  ${B}Updates$R")
    [void]$sb.AppendLine("  $DIM$status$R")
    if ($msg) { [void]$sb.AppendLine("  $GRN$msg$R") }
    [void]$sb.AppendLine("  $SEP")
    [void]$sb.AppendLine((Get-RowAction 'Check for updates / update now' ($focus -eq 0)))
    [void]$sb.AppendLine((Get-RowAction "Auto-update: $auto (toggle)" ($focus -eq 1)))
    [void]$sb.AppendLine((Get-RowAction '← Back' ($focus -eq 2)))
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("  $DIM↑/↓ move · enter select · esc back$R")
    Write-Frame $sb
    $key = Read-Key
    switch ($key) {
      'ctrlc' { Complete-Cleanup; exit 130 }
      'up'    { $focus = ($focus + $rows - 1) % $rows }
      'k'     { $focus = ($focus + $rows - 1) % $rows }
      'down'  { $focus = ($focus + 1) % $rows }
      'j'     { $focus = ($focus + 1) % $rows }
      'esc'   { return }
      'b'     { return }
      'enter' {
        switch ($focus) {
          0 {
            [Console]::CursorVisible = $true
            [Console]::Write("`n`n")
            & $ENGINE -NoProfile -ExecutionPolicy Bypass -File $UPDATE
            Wait-AnyKey
            [Console]::CursorVisible = $false
          }
          1 {
            if (Test-Path -LiteralPath $autoFlag) {
              & $ENGINE -NoProfile -ExecutionPolicy Bypass -File $UPDATE --auto off | Out-Null
              $msg = 'auto-update turned off'
            } else {
              & $ENGINE -NoProfile -ExecutionPolicy Bypass -File $UPDATE --auto on | Out-Null
              $msg = 'auto-update on — daily background check'
            }
          }
          2 { return }
        }
      }
    }
  }
}

# ---------- choose which modes appear in the in-Claude /mode picker ----------
function Show-PickerMenu {
  $focus = 0; $msg = ''
  while ($true) {
    Read-Modes
    $M = $script:ModeNames.Count
    if ($M -eq 0) { return }
    if ($focus -ge $M) { $focus = $M - 1 }
    if ($focus -lt 0) { $focus = 0 }
    $sb = New-Frame
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("  ${B}Choose what appears in /mode$R  $DIM(up to 5 — your current mode is hidden, so 4 show)$R")
    [void]$sb.AppendLine("  selected: $CYN$($script:Picker.Count)/5$R")
    if ($msg) { [void]$sb.AppendLine("  $YEL$msg$R") }
    [void]$sb.AppendLine("  $SEP")
    for ($i = 0; $i -lt $M; $i++) {
      $chk = if (Test-InPicker $script:ModeNames[$i]) { '✓' } else { ' ' }
      if ($focus -eq $i) {
        [void]$sb.AppendLine("  $REV ▸ [$chk] $($script:ModeNames[$i].PadRight(10)) $($script:ModeDescs[$i]) $R")
      } else {
        $g = if ($chk -eq '✓') { "$GRN✓$R" } else { ' ' }
        [void]$sb.AppendLine("     [$g] $CYN$($script:ModeNames[$i].PadRight(10))$R $DIM$($script:ModeDescs[$i])$R")
      }
    }
    [void]$sb.AppendLine("  $SEP")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("  $DIM↑/↓ move · space/enter toggle · esc done$R")
    Write-Frame $sb
    $key = Read-Key
    switch ($key) {
      'ctrlc' { Complete-Cleanup; exit 130 }
      'up'    { $focus = ($focus + $M - 1) % $M; $msg = '' }
      'k'     { $focus = ($focus + $M - 1) % $M; $msg = '' }
      'down'  { $focus = ($focus + 1) % $M; $msg = '' }
      'j'     { $focus = ($focus + 1) % $M; $msg = '' }
      'esc'   { return }
      'b'     { return }
      'q'     { return }
      { $_ -in 'space', 'enter' } {
        if (Switch-Picker $script:ModeNames[$focus]) { $msg = '' } else { $msg = 'picker is full (5) — uncheck one first' }
      }
    }
  }
}

# ---------- main menu: pick the default mode for new sessions ----------
function Complete-Cleanup {
  try { [Console]::CursorVisible = $true } catch {}
  try { [Console]::TreatControlCAsInput = $false } catch {}
}
function Complete-Finish {
  $sb = New-Frame
  Write-Frame $sb
  $cm = if ($script:CurrentMode) { $script:CurrentMode } else { 'custom' }
  [Console]::Write("`n  ${GRN}Done.$R Default for new sessions: $CYN$cm$R`n")
  [Console]::Write("  ${DIM}this session, switch anytime with$R $CYN/mode <name>$R`n")
  Show-Preview $null
  [Console]::Write("`n")
  Complete-Cleanup
  exit 0
}
function Get-MainFrame([int]$focus, [string]$msg) {
  $M = $script:ModeNames.Count
  $sb = New-Frame
  [void]$sb.AppendLine()
  [void]$sb.AppendLine("  ${B}Claude Code status line — Modes$R")
  $cm = if ($script:CurrentMode) { $script:CurrentMode } else { 'custom' }
  [void]$sb.AppendLine("  ${DIM}default for new sessions:$R $CYN$cm$R   $DIM★ default · ·/mode = in picker$R")
  if ($msg) { [void]$sb.AppendLine("  $GRN$msg$R") }
  [void]$sb.AppendLine("  $SEP")
  for ($i = 0; $i -lt $M; $i++) {
    if ($focus -eq $i) {
      $pt = if (Test-InPicker $script:ModeNames[$i]) { '  ·/mode' } else { '' }
      [void]$sb.AppendLine("  $REV ▸ $($script:ModeNames[$i].PadRight(10)) $($script:ModeDescs[$i])$pt $R")
    } else {
      $star = if ($script:ModeNames[$i] -eq $script:CurrentMode) { "$GRN★$R " } else { '  ' }
      $pt = if (Test-InPicker $script:ModeNames[$i]) { " $DIM·/mode$R" } else { '' }
      [void]$sb.AppendLine("   $star$CYN$($script:ModeNames[$i].PadRight(10))$R $DIM$($script:ModeDescs[$i])$R$pt")
    }
  }
  [void]$sb.AppendLine("  $SEP")
  [void]$sb.AppendLine((Get-RowAction 'Configure /mode picker ▸' ($focus -eq $M)))
  [void]$sb.AppendLine((Get-RowAction 'Updates ▸' ($focus -eq ($M + 1))))
  [void]$sb.AppendLine((Get-RowAction '+ Create new mode' ($focus -eq ($M + 2))))
  [void]$sb.AppendLine((Get-RowAction "${GRN}Quit$R" ($focus -eq ($M + 3))))
  $pv = ''
  if ($focus -lt $M) { $pv = Get-SpecPreview $script:ModeSpecs[$focus] }
  [void]$sb.AppendLine("  $SEP")
  [void]$sb.AppendLine("  ${DIM}render$R  $pv")
  [void]$sb.AppendLine()
  [void]$sb.AppendLine("  $DIM↑/↓ move · enter set default · g picker · u updates · e edit · c new · d delete · p preview · q quit$R")
  $sb
}
function Show-MainMenu {
  $focus = 0; $msg = ''
  while ($true) {
    Read-DefaultMode
    Read-Modes
    $M = $script:ModeNames.Count
    $nrows = $M + 4   # modes + Configure picker + Updates + Create + Quit
    if ($focus -ge $nrows) { $focus = $nrows - 1 }
    if ($focus -lt 0) { $focus = 0 }
    Write-Frame (Get-MainFrame $focus $msg)
    $key = Read-Key
    switch ($key) {
      'ctrlc' { Complete-Cleanup; exit 130 }
      'up'    { $focus = ($focus + $nrows - 1) % $nrows; $msg = '' }
      'k'     { $focus = ($focus + $nrows - 1) % $nrows; $msg = '' }
      'down'  { $focus = ($focus + 1) % $nrows; $msg = '' }
      'j'     { $focus = ($focus + 1) % $nrows; $msg = '' }
      'q'     { Complete-Finish }
      'esc'   { Complete-Finish }
      'g'     { Show-PickerMenu }
      'u'     { Show-UpdateMenu }
      'e'     { if ($focus -lt $M) { Edit-SlMode $focus } }
      'c'     { Edit-SlMode $null }
      'd'     { if ($focus -lt $M) { $dn = $script:ModeNames[$focus]; Remove-ModeByIndex $focus; $msg = "deleted '$dn'" } }
      'p'     { if ($focus -lt $M) { [Console]::Write("`n  "); [Console]::Write((Get-SpecPreview $script:ModeSpecs[$focus])); Wait-AnyKey } }
      'enter' {
        if ($focus -lt $M) { Set-DefaultByIndex $focus; $msg = "★ '$($script:CurrentMode)' is now the default for new sessions" }
        elseif ($focus -eq $M) { Show-PickerMenu }
        elseif ($focus -eq ($M + 1)) { Show-UpdateMenu }
        elseif ($focus -eq ($M + 2)) { Edit-SlMode $null }
        else { Complete-Finish }
      }
    }
  }
}

# ---------- run ----------
Initialize-Modes
Read-Modes
Read-Picker
Read-DefaultMode

if ($NoMenu) {   # smoke test: draw the main screen once, no key handling
  Write-Frame (Get-MainFrame 0 '')
  [Console]::Write("`n")
  exit 0
}

try {
  try { [Console]::TreatControlCAsInput = $true } catch {}
  try { [Console]::CursorVisible = $false } catch {}
  Show-MainMenu
} finally {
  Complete-Cleanup
}
