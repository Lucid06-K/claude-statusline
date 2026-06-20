#!/usr/bin/env bash
# Claude Code status line — kitchen-sink configuration
# Reads JSON from stdin piped by Claude Code

input=$(cat)

# --- Data extraction ---
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
model=$(echo "$input" | jq -r '.model.display_name // empty')
effort=$(echo "$input" | jq -r '.effort.level // empty')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
input_tokens=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // empty')
session_cost=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')
duration_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // empty')
session_id=$(echo "$input" | jq -r '.session_id // empty')
fast_mode=$(echo "$input" | jq -r '.fast_mode // empty')
rl5_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
rl5_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
rl7_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
rl7_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')
output_style=$(echo "$input" | jq -r '.output_style.name // empty')
tok_in=$(echo "$input" | jq -r '.context_window.total_input_tokens // empty')
tok_out=$(echo "$input" | jq -r '.context_window.total_output_tokens // empty')
thinking_on=$(echo "$input" | jq -r '.thinking.enabled')   # NOT `// empty` — jq's // treats false as empty

# --- Color support ---
# Truecolor if the terminal advertises it (iTerm2/Ghostty/Warp/VSCode set COLORTERM);
# otherwise fall back to a 256-color SGR param. ANSI named colors used elsewhere
# work in any terminal, so effort levels stay correct even without truecolor.
ESC=$'\033'
RESET="${ESC}[0m"
case "$COLORTERM" in
  truecolor|24bit) TRUECOLOR=1 ;;
  *)               TRUECOLOR=0 ;;
esac

# fg_rgb R G B FALLBACK_SGR -> opening escape for a foreground color
fg_rgb() {
  if [ "$TRUECOLOR" = "1" ]; then
    printf '%s[38;2;%d;%d;%dm' "$ESC" "$1" "$2" "$3"
  else
    printf '%s[%sm' "$ESC" "$4"
  fi
}

# rainbow_text TEXT -> per-character color cycle (static nod to "rainbow-animated")
rainbow_text() {
  local s="$1" out="" i ch idx
  local tc=( "255;90;90" "255;180;70" "120;220;120" "100;180;255" "200;120;255" )
  local ac=( 91 93 92 96 95 )
  for ((i=0; i<${#s}; i++)); do
    ch="${s:$i:1}"; idx=$(( i % ${#tc[@]} ))
    if [ "$TRUECOLOR" = "1" ]; then
      out+="${ESC}[38;2;${tc[$idx]}m${ch}"
    else
      out+="${ESC}[${ac[$idx]}m${ch}"
    fi
  done
  printf '%s%s' "$out" "$RESET"
}

# --- Element toggles (configure interactively: bash ~/.claude/statusline-config.sh) ---
# Each defaults to on; the conf file overrides with KEY=0 to hide.
SL_DIRECTORY=1; SL_GIT=1; SL_MODEL=1; SL_FASTMODE=1; SL_EFFORT=1
SL_CONTEXT=1; SL_CONTEXT_WARN=1; SL_RATELIMIT_5H=1; SL_RATELIMIT_7D=1
SL_BURNRATE=1; SL_COST=1; SL_COST_COLOR=1; SL_ELAPSED=1; SL_CLOCK=1
SL_OUTPUTSTYLE=1; SL_TOKENS=1; SL_THINKING=1
# Config precedence: explicit $SL_CONF (preview) > per-session mode (set via /mode) > global default.
if [ -z "${SL_CONF:-}" ]; then
  SL_CONF="${HOME}/.claude/statusline.conf"
  _sess="${HOME}/.claude/statusline.sessions/${session_id}.conf"
  [ -n "$session_id" ] && [ -f "$_sess" ] && SL_CONF="$_sess"
fi
[ -f "$SL_CONF" ] && . "$SL_CONF"

# --- Segment: Directory (folder glyph + smart path) ---
# Home -> ~ ; directly under home -> ~/name ; else last two path segments.
loc="${cwd:-$(pwd)}"
home_dir="$HOME"
if [ "$loc" = "$home_dir" ]; then
  path_disp="~"
elif [ "$loc" = "/" ]; then
  path_disp="/"
else
  parent_dir="$(dirname "$loc")"
  base="$(basename "$loc")"
  if [ "$parent_dir" = "$home_dir" ]; then
    path_disp="~/$base"
  elif [ "$parent_dir" = "/" ]; then
    path_disp="/$base"
  else
    path_disp="$(basename "$parent_dir")/$base"
  fi
fi
dir_seg="📁 $path_disp"

# --- Segment: Git branch + dirty indicator + ahead/behind upstream ---
git_seg=""
gd="${cwd:-$(pwd)}"
git_dir=""
[ "$SL_GIT" = 1 ] && git_dir=$(git -C "$gd" rev-parse --git-dir 2>/dev/null)
if [ -n "$git_dir" ]; then
  branch=$(git -C "$gd" symbolic-ref --short HEAD 2>/dev/null \
           || git -C "$gd" rev-parse --short HEAD 2>/dev/null)
  if [ -n "$branch" ]; then
    git_seg="$branch"
    git -C "$gd" status --porcelain 2>/dev/null | grep -q . && git_seg="${git_seg}*"
    # ahead/behind vs upstream: output is "behind<TAB>ahead"
    counts=$(git -C "$gd" rev-list --left-right --count '@{upstream}...HEAD' 2>/dev/null)
    if [ -n "$counts" ]; then
      behind=$(printf '%s' "$counts" | awk '{print $1+0}')
      ahead=$(printf '%s'  "$counts" | awk '{print $2+0}')
      [ "$ahead"  -gt 0 ] 2>/dev/null && git_seg="${git_seg} ${ESC}[92m⇡${ahead}${RESET}"
      [ "$behind" -gt 0 ] 2>/dev/null && git_seg="${git_seg} ${ESC}[91m⇣${behind}${RESET}"
    fi
  fi
fi

# --- Segment: Model (Claude brand orange — claude: rgb(215,119,87)) ---
model_seg="$(fg_rgb 215 119 87 '38;5;173')${model:-unknown model}${RESET}"
[ "$fast_mode" = "true" ] && [ "$SL_FASTMODE" = 1 ] && model_seg="${model_seg} ${ESC}[93m⚡${RESET}"

# --- Segment: Reasoning effort (color matches the effort selector) ---
#   low->warning(yellow)  medium->success(green)  high->permission(blue)
#   xhigh->autoAccept(magenta)  max->rainbow-animated
effort_seg=""
if [ -n "$effort" ]; then
  case "$effort" in
    low)    lvl="${ESC}[93m${effort}${RESET}" ;;
    medium) lvl="${ESC}[92m${effort}${RESET}" ;;
    high)   lvl="${ESC}[94m${effort}${RESET}" ;;
    xhigh)  lvl="${ESC}[95m${effort}${RESET}" ;;
    max)    lvl="$(rainbow_text "$effort")" ;;
    *)      lvl="$effort" ;;
  esac
  effort_seg="${lvl}"
fi

# --- Segment: Thinking off (only shown when extended thinking is disabled) ---
thinking_seg=""
[ "$thinking_on" = "false" ] && thinking_seg="${ESC}[93m🧠⨯${RESET}"

# --- Segment: Output style (only when not the default style) ---
style_seg=""
if [ -n "$output_style" ] && [ "$output_style" != "default" ] && [ "$output_style" != "null" ]; then
  style_seg="${ESC}[96m✎ ${output_style}${RESET}"
fi

# --- Segment: Tokens this session (↓ input  ↑ output) ---
hk() { awk -v n="$1" 'BEGIN{ if(n>=1e6) printf "%.1fM", n/1e6; else if(n>=1e3) printf "%.0fk", n/1e3; else printf "%d", n }'; }
tokens_seg=""
if [ -n "$tok_in" ] && [ "$tok_in" != "null" ]; then
  tokens_seg="${ESC}[90m↓${RESET}$(hk "$tok_in") ${ESC}[90m↑${RESET}$(hk "${tok_out:-0}")"
fi

# --- Helper: colored mini progress bar (green -> yellow -> red) ---
mk_bar() {
  local pct=$1 width=${2:-10} filled empty col f="" e="" i
  filled=$(( (pct * width + 50) / 100 ))
  [ "$filled" -gt "$width" ] && filled=$width
  [ "$filled" -lt 0 ] && filled=0
  empty=$(( width - filled ))
  if   [ "$pct" -ge 80 ]; then col=91   # red
  elif [ "$pct" -ge 50 ]; then col=93   # yellow
  else                         col=92   # green
  fi
  for ((i=0; i<filled; i++)); do f+="█"; done
  for ((i=0; i<empty;  i++)); do e+="░"; done
  printf '%s[90m▕%s[%dm%s%s[90m%s▏%s' "$ESC" "$ESC" "$col" "$f" "$ESC" "$e" "$RESET"
}

# --- Helper: compact countdown from an epoch timestamp (1h12m / 47m / 34s) ---
fmt_eta() {
  local target=$1 now rem h m
  now=$(date +%s)
  rem=$(( target - now ))
  [ "$rem" -lt 0 ] && rem=0
  if   [ "$rem" -ge 3600 ]; then h=$(( rem/3600 )); m=$(( (rem%3600)/60 )); printf '%dh%02dm' "$h" "$m"
  elif [ "$rem" -ge 60   ]; then printf '%dm' "$(( rem/60 ))"
  else                           printf '%ds' "$rem"
  fi
}

# --- Helper: sync a rate-limit % across sessions ---------------------------------
# Account-wide usage is monotonic within a window (until it resets), so the highest
# value any session has seen for the current window (keyed by reset time) is the most
# accurate. Each render reads/writes a shared file so every session shows the same %.
rl_synced() {                    # $1=pct  $2=reset_epoch  $3=name(5h|7d) -> echoes synced pct
  local pct="$1" reset="${2:-0}" name="$3"
  local dir="${TMPDIR:-/tmp}/cc-statusline" f
  f="$dir/rl-${name}"
  mkdir -p "$dir" 2>/dev/null
  local sreset spct
  [ -f "$f" ] && IFS=$'\t' read -r sreset spct < "$f"
  # same window as cached -> take the higher (fresher) value; new window -> start over
  if [ "$sreset" = "$reset" ] && [ -n "$spct" ] && [ "$spct" -gt "$pct" ] 2>/dev/null; then
    pct="$spct"
  fi
  printf '%s\t%s\n' "$reset" "$pct" > "$f.$$" 2>/dev/null && mv -f "$f.$$" "$f" 2>/dev/null
  printf '%s' "$pct"
}

# --- Segment: Context window usage (mini progress bar + percentage) ---
ctx_seg=""
if [ -n "$used_pct" ]; then
  printf_pct=$(printf "%.0f" "$used_pct" 2>/dev/null)
  ctx_seg="$(mk_bar "$printf_pct" 10) ${printf_pct}%"
  [ "$printf_pct" -ge 85 ] 2>/dev/null && [ "$SL_CONTEXT_WARN" = 1 ] && ctx_seg="${ctx_seg} ${ESC}[91m⚠${RESET}"   # near auto-compact
elif [ -n "$input_tokens" ]; then
  ctx_seg="ctx:${input_tokens}t"
fi

# --- Segment: Rate limit (5h window; bar + % + reset countdown, synced across sessions) ---
rl_seg=""
if [ -n "$rl5_pct" ]; then
  rp=$(printf "%.0f" "$rl5_pct" 2>/dev/null)
  rp=$(rl_synced "$rp" "$rl5_reset" "5h")
  rl_seg="5h $(mk_bar "$rp" 6) ${rp}%"
  [ -n "$rl5_reset" ] && [ "$rl5_reset" != "null" ] && rl_seg="${rl_seg} ${ESC}[90m⟳ $(fmt_eta "$rl5_reset")${RESET}"
fi

# --- Segment: 7-day rate limit (synced; only surfaces once it's a real constraint) ---
rl7_seg=""
if [ -n "$rl7_pct" ]; then
  rp7=$(printf "%.0f" "$rl7_pct" 2>/dev/null)
  rp7=$(rl_synced "$rp7" "$rl7_reset" "7d")
  if [ "$rp7" -ge 50 ] 2>/dev/null; then
    rl7_seg="7d $(mk_bar "$rp7" 6) ${rp7}%"
    [ -n "$rl7_reset" ] && [ "$rl7_reset" != "null" ] && rl7_seg="${rl7_seg} ${ESC}[90m⟳ $(fmt_eta "$rl7_reset")${RESET}"
  fi
fi

# --- Segment: Burn rate ($ per active hour) ---
burn_seg=""
if [ -n "$session_cost" ] && [ "$session_cost" != "null" ] \
   && [ -n "$duration_ms" ] && [ "$duration_ms" != "null" ] && [ "$duration_ms" -gt 10000 ] 2>/dev/null; then
  burn=$(awk -v c="$session_cost" -v d="$duration_ms" 'BEGIN{ printf "%.2f", (d>0)? c*3600000.0/d : 0 }')
  burn_seg="$(printf '$%s/h' "$burn")"
fi

# --- Segment: Session cost (color escalates with spend) ---
cost_seg=""
if [ -n "$session_cost" ] && [ "$session_cost" != "null" ]; then
  cost_fmt="$(printf '$%.2f' "$session_cost" 2>/dev/null)"
  if [ "$SL_COST_COLOR" = 1 ]; then
    ccol=$(awk -v c="$session_cost" 'BEGIN{ print (c>=5)?91:((c>=2)?93:90) }')   # >=5 red, >=2 yellow, else dim
    cost_seg="${ESC}[${ccol}m${cost_fmt}${RESET}"
  else
    cost_seg="$cost_fmt"
  fi
fi

# --- Segment: Session elapsed (wall-clock since first render this session) ---
elapsed_seg=""
if [ "$SL_ELAPSED" = 1 ] && [ -n "$session_id" ]; then
  mark_dir="${TMPDIR:-/tmp}/cc-statusline"
  mkdir -p "$mark_dir" 2>/dev/null
  find "$mark_dir" -type f -mtime +2 -delete 2>/dev/null   # prune stale session marks
  mark="$mark_dir/${session_id}.start"
  now=$(date +%s)
  if [ -f "$mark" ]; then start=$(cat "$mark" 2>/dev/null); else start=$now; printf '%s' "$now" > "$mark" 2>/dev/null; fi
  [ -z "$start" ] && start=$now
  el=$(( now - start )); [ "$el" -lt 0 ] && el=0
  if   [ "$el" -ge 3600 ]; then elapsed_seg="$(printf '⏱ %dh%02dm' "$(( el/3600 ))" "$(( (el%3600)/60 ))")"
  elif [ "$el" -ge 60   ]; then elapsed_seg="$(printf '⏱ %dm' "$(( el/60 ))")"
  else                          elapsed_seg="$(printf '⏱ %ds' "$el")"
  fi
fi

# --- Segment: Current time ---
time_seg="$(date +%H:%M)"

# --- Assemble with separators ---
SEP=" | "
parts=()

[ "$SL_DIRECTORY"    = 1 ]                          && parts+=("${dir_seg}")
[ "$SL_GIT"          = 1 ] && [ -n "$git_seg"     ] && parts+=("${git_seg}")
[ "$SL_MODEL"        = 1 ]                          && parts+=("${model_seg}")
[ "$SL_THINKING"     = 1 ] && [ -n "$thinking_seg" ] && parts+=("${thinking_seg}")
[ "$SL_EFFORT"       = 1 ] && [ -n "$effort_seg"  ] && parts+=("${effort_seg}")
[ "$SL_OUTPUTSTYLE"  = 1 ] && [ -n "$style_seg"   ] && parts+=("${style_seg}")
[ "$SL_CONTEXT"      = 1 ] && [ -n "$ctx_seg"     ] && parts+=("${ctx_seg}")
[ "$SL_TOKENS"       = 1 ] && [ -n "$tokens_seg"  ] && parts+=("${tokens_seg}")
[ "$SL_RATELIMIT_5H" = 1 ] && [ -n "$rl_seg"      ] && parts+=("${rl_seg}")
[ "$SL_RATELIMIT_7D" = 1 ] && [ -n "$rl7_seg"     ] && parts+=("${rl7_seg}")
[ "$SL_BURNRATE"     = 1 ] && [ -n "$burn_seg"    ] && parts+=("${burn_seg}")
[ "$SL_COST"         = 1 ] && [ -n "$cost_seg"    ] && parts+=("${cost_seg}")
[ "$SL_ELAPSED"      = 1 ] && [ -n "$elapsed_seg" ] && parts+=("${elapsed_seg}")
[ "$SL_CLOCK"        = 1 ]                          && parts+=("${time_seg}")

# Join with separator
result=""
for part in "${parts[@]}"; do
  if [ -z "$result" ]; then
    result="$part"
  else
    result="${result}${SEP}${part}"
  fi
done

printf "%s" "$result"
