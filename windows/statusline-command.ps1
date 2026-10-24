# Claude Code status line — Windows (PowerShell) renderer
# Native port of statusline-command.sh: reads the JSON Claude Code pipes to stdin
# and prints one ANSI-coloured line. Works on Windows PowerShell 5.1 and pwsh 7+.
# No dependencies — JSON is parsed natively (no jq).

$ErrorActionPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

# --- stdin -> JSON ------------------------------------------------------------
# $input covers pipeline/in-process invocation (slconfig previews); Console.In
# covers `powershell -File` with redirected stdin (how Claude Code calls us).
$raw = ($input | Out-String)
if (-not $raw.Trim()) { try { $raw = [Console]::In.ReadToEnd() } catch {} }
$j = $null
if ($raw -and $raw.Trim()) { try { $j = ConvertFrom-Json $raw } catch {} }

# --- data extraction (missing paths just yield $null — the jq `// ""` analogue) -
$cwd       = if ($j.workspace.current_dir) { [string]$j.workspace.current_dir } elseif ($j.cwd) { [string]$j.cwd } else { '' }
$model     = [string]$j.model.display_name
$effort    = [string]$j.effort.level
$usedPct   = $j.context_window.used_percentage
$inputToks = $j.context_window.current_usage.input_tokens
$sessCost  = $j.cost.total_cost_usd
$durMs     = $j.cost.total_duration_ms
$sessionId = [string]$j.session_id
$fastMode  = $j.fast_mode
$rl5Pct    = $j.rate_limits.five_hour.used_percentage
$rl5Reset  = $j.rate_limits.five_hour.resets_at
$rl7Pct    = $j.rate_limits.seven_day.used_percentage
$rl7Reset  = $j.rate_limits.seven_day.resets_at
$styleName = [string]$j.output_style.name
$tokIn     = $j.context_window.total_input_tokens
$tokOut    = $j.context_window.total_output_tokens
$thinking  = $j.thinking.enabled

$HOME_DIR = $env:USERPROFILE
if (-not $HOME_DIR) { $HOME_DIR = [Environment]::GetFolderPath('UserProfile') }
$CLAUDE = Join-Path $HOME_DIR '.claude'
$inv = [System.Globalization.CultureInfo]::InvariantCulture

# --- colour support -------------------------------------------------------------
# Truecolor when the terminal advertises it (COLORTERM) or we're in Windows
# Terminal (WT_SESSION); otherwise fall back to a 256-colour SGR param. ANSI
# named colours used elsewhere work in any terminal.
$E = [char]27
$RESET = "$E[0m"
$TRUECOLOR = ($env:COLORTERM -match '^(truecolor|24bit)$') -or [bool]$env:WT_SESSION

function fg_rgb([int]$r, [int]$g, [int]$b, [string]$fallback) {
  if ($TRUECOLOR) { "$E[38;2;$r;$g;${b}m" } else { "$E[${fallback}m" }
}

# rainbow_text TEXT -> per-character colour cycle (static nod to "rainbow-animated")
function rainbow_text([string]$s) {
  $tc = @('255;90;90', '255;180;70', '120;220;120', '100;180;255', '200;120;255')
  $ac = @(91, 93, 92, 96, 95)
  $out = ''
  for ($i = 0; $i -lt $s.Length; $i++) {
    $idx = $i % 5
    if ($TRUECOLOR) { $out += "$E[38;2;$($tc[$idx])m$($s[$i])" } else { $out += "$E[$($ac[$idx])m$($s[$i])" }
  }
  "$out$RESET"
}

# --- element toggles (configure interactively: slconfig) ------------------------
# Each defaults to on; the conf file overrides with KEY=0 to hide.
$SL = @{}
$SL_KEYS = @('SL_DIRECTORY','SL_GIT','SL_MODEL','SL_FASTMODE','SL_EFFORT','SL_CONTEXT','SL_CONTEXT_WARN',
             'SL_RATELIMIT_5H','SL_RATELIMIT_7D','SL_BURNRATE','SL_COST','SL_COST_COLOR','SL_ELAPSED',
             'SL_CLOCK','SL_OUTPUTSTYLE','SL_TOKENS','SL_THINKING')
foreach ($k in $SL_KEYS) { $SL[$k] = 1 }

$sidSafe = ''
if ($sessionId) { $sidSafe = $sessionId -replace '[^\w\.\-]', '' }

# Config precedence: explicit $env:SL_CONF (previews) > per-session mode (set via
# /mode) > global default. Parsed as strict KEY=0/1 — never executed (same
# hardening as the bash renderer: a mode name is an inert display string).
$conf = $env:SL_CONF
if (-not $conf) {
  $conf = Join-Path $CLAUDE 'statusline.conf'
  if ($sidSafe) {
    $sess = Join-Path $CLAUDE "statusline.sessions\$sidSafe.conf"
    if (Test-Path -LiteralPath $sess) { $conf = $sess }
  }
}
if ($conf -and (Test-Path -LiteralPath $conf)) {
  foreach ($line in [System.IO.File]::ReadAllLines($conf)) {
    if ($line -match '^(SL_[A-Z0-9_]+)=([01])$' -and $SL.ContainsKey($Matches[1])) { $SL[$Matches[1]] = [int]$Matches[2] }
  }
}

# --- daily auto-update (opt-in: ~/.claude/statusline.auto-update) ----------------
# Cheap throttle (one stamp read + date) every render; once a day it detaches a
# hidden background fast-forward pull so it never blocks or slows the status line.
if (Test-Path -LiteralPath (Join-Path $CLAUDE 'statusline.auto-update')) {
  $stampF = Join-Path $CLAUDE 'statusline.update-check'
  $today = (Get-Date).ToString('yyyy-MM-dd')
  $stamp = ''
  if (Test-Path -LiteralPath $stampF) { $stamp = ([System.IO.File]::ReadAllText($stampF)).Trim() }
  if ($stamp -ne $today) {
    try {
      [System.IO.File]::WriteAllText($stampF, $today)
      $me = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
      $upd = Join-Path $CLAUDE 'statusline-update.ps1'
      if ($me -and (Test-Path -LiteralPath $upd)) {
        Start-Process -FilePath $me -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$upd`"", '--background' -WindowStyle Hidden | Out-Null
      }
    } catch {}
  }
}

# --- segment: directory (folder glyph + smart path) ------------------------------
# Home -> ~ ; directly under home -> ~\name ; else last two path segments.
$loc = if ($cwd) { $cwd } else { (Get-Location).Path }
$loc = $loc -replace '/', '\'
$homeN = $HOME_DIR.TrimEnd('\')
$locN = $loc.TrimEnd('\')
if ($locN -match '^[A-Za-z]:$') { $locN += '\' }
$pathDisp = $locN
if ([string]::Equals($locN, $homeN, [StringComparison]::OrdinalIgnoreCase)) {
  $pathDisp = '~'
} else {
  $base = Split-Path -Leaf $locN
  $parent = Split-Path -Parent $locN
  if ($parent -and [string]::Equals($parent.TrimEnd('\'), $homeN, [StringComparison]::OrdinalIgnoreCase)) {
    $pathDisp = "~\$base"
  } elseif ($parent) {
    $pp = Split-Path -Leaf $parent
    if ($pp -and $pp -ne $parent) { $pathDisp = "$pp\$base" }
  }
}
$dirSeg = "📁 $pathDisp"

# --- segment: git branch + dirty indicator + ahead/behind upstream ----------------
# One `git status --porcelain=v2 --branch` call gives branch, dirty state and
# ahead/behind counts together (process spawns are expensive on Windows).
$gitSeg = ''
if ($SL.SL_GIT -eq 1 -and (Get-Command git -ErrorAction SilentlyContinue)) {
  $gd = if ($cwd) { $cwd } else { (Get-Location).Path }
  $st = @(git -C $gd status --porcelain=v2 --branch 2>$null)
  if ($LASTEXITCODE -eq 0 -and $st.Count -gt 0) {
    $branch = ''; $oid = ''; $ahead = 0; $behind = 0; $dirty = $false
    foreach ($ln in $st) {
      $s = [string]$ln
      if     ($s.StartsWith('# branch.head ')) { $branch = $s.Substring(14) }
      elseif ($s.StartsWith('# branch.oid '))  { $oid = $s.Substring(13) }
      elseif ($s.StartsWith('# branch.ab '))   { if ($s -match '\+(\d+) -(\d+)') { $ahead = [int]$Matches[1]; $behind = [int]$Matches[2] } }
      elseif (-not $s.StartsWith('#') -and $s.Trim()) { $dirty = $true }
    }
    if ($branch -eq '(detached)' -and $oid -and $oid -ne '(initial)') { $branch = $oid.Substring(0, [Math]::Min(7, $oid.Length)) }
    if ($branch) {
      $gitSeg = $branch
      if ($dirty) { $gitSeg += '*' }
      if ($ahead -gt 0)  { $gitSeg += " $E[92m⇡$ahead$RESET" }
      if ($behind -gt 0) { $gitSeg += " $E[91m⇣$behind$RESET" }
    }
  }
}

# --- segment: model (Claude brand orange — claude: rgb(215,119,87)) ---------------
$ORANGE = fg_rgb 215 119 87 '38;5;173'
$modelSeg = "$ORANGE$(if ($model) { $model } else { 'unknown model' })$RESET"
if ($fastMode -eq $true -and $SL.SL_FASTMODE -eq 1) { $modelSeg += " $E[93m⚡$RESET" }

# --- segment: reasoning effort (colour matches the effort selector) ---------------
#   low->yellow  medium->green  high->blue  xhigh->magenta  max->rainbow
$effortSeg = ''
if ($effort) {
  switch ($effort) {
    'low'    { $effortSeg = "$E[93m$effort$RESET" }
    'medium' { $effortSeg = "$E[92m$effort$RESET" }
    'high'   { $effortSeg = "$E[94m$effort$RESET" }
    'xhigh'  { $effortSeg = "$E[95m$effort$RESET" }
    'max'    { $effortSeg = rainbow_text $effort }
    default  { $effortSeg = $effort }
  }
}

# --- segment: thinking off (only shown when extended thinking is disabled) --------
$thinkSeg = ''
if ($thinking -is [bool] -and -not $thinking) { $thinkSeg = "$E[93m🧠⨯$RESET" }

# --- segment: output style (only when not the default style) ----------------------
$styleSeg = ''
if ($styleName -and $styleName -ne 'default' -and $styleName -ne 'null') { $styleSeg = "$E[96m✎ $styleName$RESET" }

# --- segment: tokens this session (↓ input  ↑ output) ------------------------------
function hk($n) {
  $d = [double]$n
  if ($d -ge 1e6) { [string]::Format($inv, '{0:0.0}M', $d / 1e6) }
  elseif ($d -ge 1e3) { [string]::Format($inv, '{0:0}k', $d / 1e3) }
  else { [string]::Format($inv, '{0:0}', $d) }
}
$tokensSeg = ''
if ($null -ne $tokIn -and "$tokIn" -ne '') {
  $to = if ($null -ne $tokOut -and "$tokOut" -ne '') { $tokOut } else { 0 }
  $tokensSeg = "$E[90m↓$RESET$(hk $tokIn) $E[90m↑$RESET$(hk $to)"
}

# --- helper: coloured mini progress bar (green -> yellow -> red) --------------------
function mk_bar([int]$pct, [int]$width = 10) {
  $filled = [int][Math]::Floor(($pct * $width + 50) / 100)
  if ($filled -gt $width) { $filled = $width }
  if ($filled -lt 0) { $filled = 0 }
  $empty = $width - $filled
  $col = if ($pct -ge 80) { 91 } elseif ($pct -ge 50) { 93 } else { 92 }
  "$E[90m▕$E[${col}m$('█' * $filled)$E[90m$('░' * $empty)▏$RESET"
}

# --- helper: compact countdown (1h12m / 47m / 34s) from unix seconds or a date string
function to_epoch($v) {
  if ($null -eq $v -or "$v" -eq '' -or "$v" -eq 'null') { return $null }
  $n = 0L
  if ([long]::TryParse("$v", [ref]$n)) { return $n }
  try { return [System.DateTimeOffset]::Parse("$v", $inv).ToUnixTimeSeconds() } catch { return $null }
}
function fmt_eta([long]$target) {
  $rem = $target - [System.DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  if ($rem -lt 0) { $rem = 0 }
  if ($rem -ge 3600) { '{0}h{1:00}m' -f [Math]::Floor($rem / 3600), [Math]::Floor(($rem % 3600) / 60) }
  elseif ($rem -ge 60) { '{0}m' -f [Math]::Floor($rem / 60) }
  else { "${rem}s" }
}

# --- helper: sync a rate-limit % across sessions ------------------------------------
# Account-wide usage is monotonic within a window (until it resets), so the highest
# value any session has seen for the current window (keyed by reset time) is the most
# accurate. Each render reads/writes a shared file so every session shows the same %.
$tmpBase = if ($env:CC_SL_TMP) { $env:CC_SL_TMP } else { $env:TEMP }
$slTmp = Join-Path $tmpBase 'cc-statusline'
New-Item -ItemType Directory -Force -Path $slTmp | Out-Null

function rl_synced([int]$pct, $reset, [string]$name) {
  $f = Join-Path $slTmp "rl-$name"
  $key = "$reset"
  try {
    if (Test-Path -LiteralPath $f) {
      $parts = ([System.IO.File]::ReadAllText($f)).Trim() -split "`t"
      if ($parts.Count -ge 2 -and $parts[0] -eq $key) {
        $sp = 0
        if ([int]::TryParse($parts[1], [ref]$sp) -and $sp -gt $pct) { $pct = $sp }
      }
    }
    $tmpF = "$f.$PID"
    [System.IO.File]::WriteAllText($tmpF, "$key`t$pct")
    Move-Item -LiteralPath $tmpF -Destination $f -Force
  } catch {}
  $pct
}

# --- segment: context window usage (mini progress bar + percentage) -----------------
$ctxSeg = ''
if ($null -ne $usedPct -and "$usedPct" -ne '') {
  $p = [int][Math]::Round([double]$usedPct)
  $ctxSeg = "$E[90m»«$RESET$(mk_bar $p 6) $p%"   # »« = compaction (context squeeze)
  if ($p -ge 85 -and $SL.SL_CONTEXT_WARN -eq 1) { $ctxSeg += " $E[91m⚠$RESET" }   # near auto-compact
} elseif ($null -ne $inputToks -and "$inputToks" -ne '') {
  $ctxSeg = "ctx:${inputToks}t"
}

# --- segment: rate limit (5h window; bar + % + reset countdown, synced) --------------
$rlSeg = ''
if ($null -ne $rl5Pct -and "$rl5Pct" -ne '') {
  $rp = [int][Math]::Round([double]$rl5Pct)
  $rp = rl_synced $rp $rl5Reset '5h'
  $rlSeg = "5h $(mk_bar $rp 6) $rp%"
  # reset countdown only once the window is a real constraint (>=80%), matching the docs
  $ep5 = to_epoch $rl5Reset
  if ($rp -ge 80 -and $null -ne $ep5) { $rlSeg += " $E[90m⟳ $(fmt_eta $ep5)$RESET" }
}

# --- segment: 7-day rate limit (weekly allowance; bar + %, synced across sessions) ---
$rl7Seg = ''
if ($null -ne $rl7Pct -and "$rl7Pct" -ne '') {
  $rp7 = [int][Math]::Round([double]$rl7Pct)
  $rp7 = rl_synced $rp7 $rl7Reset '7d'
  $rl7Seg = "7d $(mk_bar $rp7 6) $rp7%"
  $ep7 = to_epoch $rl7Reset
  if ($rp7 -ge 80 -and $null -ne $ep7) { $rl7Seg += " $E[90m⟳ $(fmt_eta $ep7)$RESET" }
}

# --- segment: burn rate ($ per active hour) -------------------------------------------
$burnSeg = ''
if ($null -ne $sessCost -and "$sessCost" -ne '' -and $null -ne $durMs -and "$durMs" -ne '' -and [double]$durMs -gt 10000) {
  $burn = [double]$sessCost * 3600000.0 / [double]$durMs
  $burnSeg = [string]::Format($inv, '${0:0.00}/h', $burn)
}

# --- segment: session cost (colour escalates with spend) ------------------------------
$costSeg = ''
if ($null -ne $sessCost -and "$sessCost" -ne '') {
  $cf = [string]::Format($inv, '${0:0.00}', [double]$sessCost)
  if ($SL.SL_COST_COLOR -eq 1) {
    $cc = if ([double]$sessCost -ge 5) { 91 } elseif ([double]$sessCost -ge 2) { 93 } else { 90 }   # >=5 red, >=2 yellow, else dim
    $costSeg = "$E[${cc}m$cf$RESET"
  } else { $costSeg = $cf }
}

# --- segment: session elapsed (wall-clock since first render this session) ------------
$elapsedSeg = ''
if ($SL.SL_ELAPSED -eq 1 -and $sidSafe) {
  try {
    $mark = Join-Path $slTmp "$sidSafe.start"
    $now = [System.DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    Get-ChildItem -LiteralPath $slTmp -File | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-2) } | Remove-Item -Force   # prune stale marks
    $start = $now
    if (Test-Path -LiteralPath $mark) {
      $t = 0L
      if ([long]::TryParse(([System.IO.File]::ReadAllText($mark)).Trim(), [ref]$t)) { $start = $t }
    } else {
      [System.IO.File]::WriteAllText($mark, "$now")
    }
    $el = $now - $start
    if ($el -lt 0) { $el = 0 }
    if ($el -ge 3600) { $elapsedSeg = '⏱ {0}h{1:00}m' -f [Math]::Floor($el / 3600), [Math]::Floor(($el % 3600) / 60) }
    elseif ($el -ge 60) { $elapsedSeg = '⏱ {0}m' -f [Math]::Floor($el / 60) }
    else { $elapsedSeg = "⏱ ${el}s" }
  } catch {}
}

# --- segment: current time --------------------------------------------------------------
$timeSeg = (Get-Date).ToString('HH:mm')

# --- assemble with separators ------------------------------------------------------------
$parts = New-Object System.Collections.Generic.List[string]
if ($SL.SL_DIRECTORY -eq 1)                  { $parts.Add($dirSeg) }
if ($SL.SL_GIT -eq 1 -and $gitSeg)           { $parts.Add($gitSeg) }
if ($SL.SL_MODEL -eq 1)                      { $parts.Add($modelSeg) }
if ($SL.SL_THINKING -eq 1 -and $thinkSeg)    { $parts.Add($thinkSeg) }
if ($SL.SL_EFFORT -eq 1 -and $effortSeg)     { $parts.Add($effortSeg) }
if ($SL.SL_OUTPUTSTYLE -eq 1 -and $styleSeg) { $parts.Add($styleSeg) }
if ($SL.SL_CONTEXT -eq 1 -and $ctxSeg)       { $parts.Add($ctxSeg) }
if ($SL.SL_TOKENS -eq 1 -and $tokensSeg)     { $parts.Add($tokensSeg) }
if ($SL.SL_RATELIMIT_5H -eq 1 -and $rlSeg)   { $parts.Add($rlSeg) }
if ($SL.SL_RATELIMIT_7D -eq 1 -and $rl7Seg)  { $parts.Add($rl7Seg) }
if ($SL.SL_BURNRATE -eq 1 -and $burnSeg)     { $parts.Add($burnSeg) }
if ($SL.SL_COST -eq 1 -and $costSeg)         { $parts.Add($costSeg) }
if ($SL.SL_ELAPSED -eq 1 -and $elapsedSeg)   { $parts.Add($elapsedSeg) }
if ($SL.SL_CLOCK -eq 1)                      { $parts.Add($timeSeg) }

$result = $parts -join ' | '

# In-process callers (slconfig previews) capture pipeline output; external callers
# (Claude Code) get exact UTF-8 bytes with no trailing newline.
if ($env:CC_SL_INPROC -eq '1') { $result } else { [Console]::Out.Write($result) }
