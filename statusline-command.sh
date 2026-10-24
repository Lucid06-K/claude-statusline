#!/usr/bin/env bash
# Claude Code status line — kitchen-sink configuration
# Reads JSON from stdin piped by Claude Code

input=$(cat)

# --- Data extraction ---
# One jq invocation for every field (was 17 separate `echo | jq` pipelines — ~100ms
# of fork/exec on every single render), plus two derived values (burn rate, cost colour)
# so the render needs no awk at all.
#
# Fields are joined with US (U+001F), NOT tab. Tab is an IFS *whitespace* character, so
# `IFS=$'\t' read` collapses runs of tabs and strips leading/trailing ones — every field
# after an empty one then shifts left by one and the whole line shows the wrong numbers.
# Claude Code legitimately omits fields all the time: `effort` only exists on reasoning
# models, `rate_limits` only appears after the first API response (and five_hour /
# seven_day are each optional on their own), and `used_percentage` is null until the
# first message. US is not IFS whitespace, so empty fields stay empty and the columns
# stay aligned.
#
# Every value is stringified (null -> "") and scrubbed of US/CR/LF, so no value can forge
# a field boundary or inject a line break into the status line.
US=$'\037'
IFS="$US" read -r cwd model effort used_pct input_tokens session_cost duration_ms \
  session_id fast_mode rl5_pct rl5_reset rl7_pct rl7_reset output_style tok_in tok_out \
  thinking_on burn_raw cost_col < <(
  printf '%s' "$input" | jq -r '
    def s: if . == null then "" else tostring end;
    def c: s | split("\u001f") | join(" ")
             | split("\n")     | join(" ")
             | split("\r")     | join(" ");
    (.cost.total_cost_usd)    as $cost |
    (.cost.total_duration_ms) as $dur  |
    [ (.workspace.current_dir // .cwd),
      .model.display_name,
      .effort.level,
      .context_window.used_percentage,
      .context_window.total_input_tokens,
      $cost,
      $dur,
      .session_id,
      .fast_mode,
      .rate_limits.five_hour.used_percentage,
      .rate_limits.five_hour.resets_at,
      .rate_limits.seven_day.used_percentage,
      .rate_limits.seven_day.resets_at,
      .output_style.name,
      .context_window.total_input_tokens,
      .context_window.total_output_tokens,
      .thinking.enabled,
      (if ($cost != null and $dur != null and $dur > 10000)
         then ($cost * 3600000 / $dur) else null end),
      (if   $cost == null then null
       elif $cost >= 5    then 91
       elif $cost >= 2    then 93
       else                    90 end)
    ] | map(c) | join("\u001f")' 2>/dev/null)   # malformed stdin -> empty fields, not a
                                                 # jq parse error on the status line's stderr

# One `date` for the whole render (was three, plus another inside fmt_eta).
read -r NOW TODAY CLOCK < <(date '+%s %Y-%m-%d %H:%M')

# --- Color support ---
# Truecolor if the terminal advertises it (iTerm2/Ghostty/Warp/VSCode set COLORTERM);
# otherwise fall back to a 256-color SGR param. ANSI named colors used elsewhere
# work in any terminal, so effort levels stay correct even without truecolor.
ESC=$'\033'
# Reset the *foreground only* (39), not everything (0). Claude Code renders the status
# line inside <Text dimColor>, so a full SGR reset switches the host's dim off partway
# through the line and every segment after the first renders brighter than the rest.
# Nothing here sets bold/dim/background, so 39 undoes every colour this script emits.
RESET="${ESC}[39m"
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
# Off by default: it is the one element that needs a network call (see statusline-usage.sh).
SL_MODEL_LIMIT=0

# The session id keys a conf path and a temp file, so it must be a plain token. Anything
# else is treated as "no session" rather than interpolated into a path.
case "$session_id" in
  ''|.|..|*[!A-Za-z0-9._-]*) session_id="" ;;
esac

# Config precedence: explicit $SL_CONF (preview) > per-session mode (set via /mode) > global default.
if [ -z "${SL_CONF:-}" ]; then
  SL_CONF="${HOME}/.claude/statusline.conf"
  _sess="${HOME}/.claude/statusline.sessions/${session_id}.conf"
  [ -n "$session_id" ] && [ -f "$_sess" ] && SL_CONF="$_sess"
fi
# Parse the conf as KEY=VALUE — never `source` it. A mode name is written into the
# conf by slconfig, so sourcing would execute arbitrary code from a mode name on
# every render. Toggles accept only 0/1; SL_MODE is a display-only string.
if [ -f "$SL_CONF" ]; then
  while IFS='=' read -r _k _v || [ -n "$_k" ]; do
    case "$_k" in
      SL_MODE) SL_MODE="$_v" ;;
      SL_*)
        case "$_k" in *[!A-Z0-9_]*) continue ;; esac     # reject anything but A-Z/0-9/_ in the key
        case "$_v" in 0|1) printf -v "$_k" '%s' "$_v" ;; esac ;;
    esac
  done < "$SL_CONF"
fi

# --- Shared state dir (session start marks + rate-limit cache) ---
STATE_DIR="${TMPDIR:-/tmp}/cc-statusline"
mkdir -p "$STATE_DIR" 2>/dev/null
[ -f "$HOME/.claude/statusline.dump" ] && printf '%s' "$input" > "$STATE_DIR/dump-${session_id:-none}.json" 2>/dev/null

# --- Daily auto-update (opt-in: ~/.claude/statusline.auto-update) ---
# Cheap throttle (one builtin read) every render; once a day it detaches a background
# fast-forward pull so it never blocks or slows the status line.
if [ -f "${HOME}/.claude/statusline.auto-update" ]; then
  _ust="${HOME}/.claude/statusline.update-check"; _uwas=""
  { read -r _uwas < "$_ust"; } 2>/dev/null
  if [ "$_uwas" != "$TODAY" ]; then
    printf '%s' "$TODAY" > "$_ust" 2>/dev/null
    ( bash "${HOME}/.claude/statusline-update.sh" --background >/dev/null 2>&1 & ) >/dev/null 2>&1
  fi
fi

# --- Segment: Directory (folder glyph + smart path) ---
# Home -> ~ ; directly under home -> ~/name ; else last two path segments.
loc="${cwd:-$PWD}"
case "$loc" in */) [ "$loc" = "/" ] || loc="${loc%/}" ;; esac
if [ "$loc" = "$HOME" ]; then
  path_disp="~"
elif [ "$loc" = "/" ]; then
  path_disp="/"
else
  base="${loc##*/}"
  parent_dir="${loc%/*}"; [ -z "$parent_dir" ] && parent_dir="/"
  if [ "$parent_dir" = "$HOME" ]; then
    path_disp="~/$base"
  elif [ "$parent_dir" = "/" ]; then
    path_disp="/$base"
  else
    path_disp="${parent_dir##*/}/$base"
  fi
fi
dir_seg="📁 $path_disp"

# --- Segment: Git branch + dirty indicator + ahead/behind upstream ---
# One `git status` carries the branch, the upstream ahead/behind counts and dirtiness;
# the four separate git invocations this replaces cost ~80ms of every render.
# --no-optional-locks stops the status line from taking index.lock several times a
# second, which otherwise races the user's own git commands (and is what Claude Code's
# own status line guidance asks for).
git_seg=""
if [ "$SL_GIT" = 1 ]; then
  gd="${cwd:-$PWD}"
  read -r branch ahead behind dirty < <(
    git --no-optional-locks -C "$gd" status --porcelain=v2 --branch 2>/dev/null | awk '
      /^# branch\.head /{ b = $3; next }
      /^# branch\.ab /  { a = $3 + 0; d = -($4 + 0); next }
      /^#/              { next }
                        { dirty = 1 }
      END { if (b == "") exit 1; printf "%s %d %d %d\n", b, a, d, dirty }'
  )
  if [ -n "${branch:-}" ]; then
    [ "$branch" = "(detached)" ] && branch=$(git --no-optional-locks -C "$gd" rev-parse --short HEAD 2>/dev/null)
    git_seg="$branch"
    [ "${dirty:-0}"  = 1 ] && git_seg="${git_seg}*"
    [ "${ahead:-0}"  -gt 0 ] 2>/dev/null && git_seg="${git_seg} ${ESC}[92m⇡${ahead}${RESET}"
    [ "${behind:-0}" -gt 0 ] 2>/dev/null && git_seg="${git_seg} ${ESC}[91m⇣${behind}${RESET}"
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
if [ -n "$output_style" ] && [ "$output_style" != "default" ]; then
  style_seg="${ESC}[96m✎ ${output_style}${RESET}"
fi

# --- Helper: humanise a token count (no awk fork) ---
hk() {
  local n="${1:-0}"
  case "$n" in ''|*[!0-9]*) printf '0'; return ;; esac
  if   [ "$n" -ge 1000000 ]; then printf '%d.%dM' $(( n / 1000000 )) $(( (n % 1000000) / 100000 ))
  elif [ "$n" -ge 1000    ]; then printf '%dk'    $(( (n + 500) / 1000 ))
  else                            printf '%d'     "$n"
  fi
}

# --- Segment: Context tokens (↓ tokens in the window  ↑ last response) ---
# Not session totals: total_input_tokens is what sits in the context window right now
# (cache reads included) and total_output_tokens is the most recent API response only.
tokens_seg=""
if [ -n "$tok_in" ]; then
  tokens_seg="${ESC}[90m↓${RESET}$(hk "$tok_in") ${ESC}[90m↑${RESET}$(hk "${tok_out:-0}")"
fi

# --- Helper: colored mini progress bar (green -> yellow -> red) ---
# Filled and empty cells must come from the same East Asian width class or the bar
# changes width as it fills: U+2588 FULL BLOCK is Ambiguous (two columns wherever the
# terminal or locale widens ambiguous glyphs) while U+2591 LIGHT SHADE is Neutral
# (always one). U+2592 MEDIUM SHADE is Ambiguous like the block and like both end caps,
# so the bar now occupies the same number of columns at every fill level.
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
  for ((i=0; i<empty;  i++)); do e+="▒"; done
  printf '%s[90m▕%s[%dm%s%s[90m%s▏%s' "$ESC" "$ESC" "$col" "$f" "$ESC" "$e" "$RESET"
}

# --- Helper: compact countdown from an epoch timestamp (1h12m / 47m / 34s) ---
fmt_eta() {
  local target=$1 rem h m
  case "$target" in ''|*[!0-9]*) return ;; esac    # non-numeric would abort the arithmetic
  rem=$(( target - NOW ))
  [ "$rem" -lt 0 ] && rem=0
  if   [ "$rem" -ge 3600 ]; then h=$(( rem/3600 )); m=$(( (rem%3600)/60 )); printf '%dh%02dm' "$h" "$m"
  elif [ "$rem" -ge 60   ]; then printf '%dm' "$(( rem/60 ))"
  else                           printf '%ds' "$rem"
  fi
}

# --- Helper: share a rate-limit reading across sessions -------------------------------
# The payload is authoritative whenever Claude Code sends one, and each reading is
# written to a shared file so a session that has none yet (rate_limits is absent until
# that session's first API response) can still show the account-wide number.
#
# It deliberately does NOT keep the highest value seen: the 5h and 7d limits are rolling
# windows, so usage genuinely falls as old activity ages out, and a max-wins cache then
# over-reports for the rest of the window.
rl_shared() {                    # $1=pct ("" if absent)  $2=reset_epoch  $3=name(5h|7d)
  # Note: $f must be assigned separately — inside a single `local`, bash creates every
  # name as an empty local before assigning, so "$name" would expand to nothing here.
  local pct="$1" reset="$2" name="$3" sreset spct f
  f="$STATE_DIR/rl-$name"
  if [ -n "$pct" ]; then
    case "$reset" in ''|*[!0-9]*) reset=0 ;; esac
    printf '%s\t%s\n' "$reset" "$pct" > "$f.$$" 2>/dev/null && mv -f "$f.$$" "$f" 2>/dev/null
    printf '%s' "$pct"
    return
  fi
  # Nothing in this payload — fall back to another session's reading, but only while
  # that window is still open, so a stale number can never outlive its own reset.
  [ -f "$f" ] && IFS=$'\t' read -r sreset spct < "$f"
  case "${sreset:-}" in ''|*[!0-9]*) return ;; esac
  [ "$sreset" -gt "$NOW" ] 2>/dev/null && printf '%s' "$spct"
}

# --- Segment: Context window usage (mini progress bar + percentage) ---
ctx_seg=""
if [ -n "$used_pct" ]; then
  printf_pct=$(printf "%.0f" "$used_pct" 2>/dev/null)
  ctx_seg="${ESC}[90m»«${RESET}$(mk_bar "$printf_pct" 6) ${printf_pct}%"   # »« = compaction (context squeeze)
  # U+FE0E pins ⚠ to its text presentation: without it the glyph is one column to a
  # width calculation but two to a terminal that draws it as an emoji, and the line
  # smears when the warning appears.
  [ "$printf_pct" -ge 85 ] 2>/dev/null && [ "$SL_CONTEXT_WARN" = 1 ] && ctx_seg="${ctx_seg} ${ESC}[91m⚠︎${RESET}"
elif [ -n "$input_tokens" ]; then
  ctx_seg="ctx:$(hk "$input_tokens")t"
fi

# --- Segment: Rate limit (5h window; bar + % + reset countdown, shared across sessions) ---
rl_seg=""
if [ -n "$rl5_pct" ]; then rp=$(printf "%.0f" "$rl5_pct" 2>/dev/null); else rp=""; fi
rp=$(rl_shared "$rp" "$rl5_reset" "5h")
if [ -n "$rp" ]; then
  rl_seg="5h $(mk_bar "$rp" 6) ${rp}%"
  # reset countdown only once the window is a real constraint (>=80%), matching the docs
  if [ "$rp" -ge 80 ] 2>/dev/null; then
    _eta=$(fmt_eta "$rl5_reset")
    [ -n "$_eta" ] && rl_seg="${rl_seg} ${ESC}[90m⟳ ${_eta}${RESET}"
  fi
fi

# --- Segment: 7-day rate limit (weekly allowance; bar + %, shared across sessions) ---
rl7_seg=""
if [ -n "$rl7_pct" ]; then rp7=$(printf "%.0f" "$rl7_pct" 2>/dev/null); else rp7=""; fi
rp7=$(rl_shared "$rp7" "$rl7_reset" "7d")
if [ -n "$rp7" ]; then
  rl7_seg="7d $(mk_bar "$rp7" 6) ${rp7}%"
  if [ "$rp7" -ge 80 ] 2>/dev/null; then
    _eta7=$(fmt_eta "$rl7_reset")
    [ -n "$_eta7" ] && rl7_seg="${rl7_seg} ${ESC}[90m⟳ ${_eta7}${RESET}"
  fi
fi

# --- Segment: Per-model weekly limit (Fable / Opus / Sonnet caps) ---
# Claude Code never sends these: its status-line payload carries five_hour and seven_day
# and nothing else. statusline-usage.sh fetches them from the endpoint /usage itself uses
# and leaves a cache here; this reads that cache (no network, no forks) and kicks off a
# refresh in the background at most once every USAGE_TTL seconds.
mlim_seg=""
if [ "$SL_MODEL_LIMIT" = 1 ]; then
  USAGE_TTL=300                                   # refresh at most every 5 minutes
  USAGE_MAX_AGE=3600                              # older than this, show nothing rather than a lie
  _ustamp=0; { read -r _ustamp < "$STATE_DIR/usage-fetch"; } 2>/dev/null
  case "${_ustamp:-}" in ''|*[!0-9]*) _ustamp=0 ;; esac
  if [ $(( NOW - _ustamp )) -ge "$USAGE_TTL" ]; then
    printf '%s' "$NOW" > "$STATE_DIR/usage-fetch" 2>/dev/null   # claim the slot before forking,
                                                                # so N sessions rendering at once
                                                                # spawn one fetch, not N
    ( bash "${HOME}/.claude/statusline-usage.sh" >/dev/null 2>&1 & ) >/dev/null 2>&1
  fi
  if [ -f "$STATE_DIR/usage-scoped" ]; then
    _ufetched=0; _uparts=()
    while IFS=$'\t' read -r _uname _upct _ureset || [ -n "$_uname" ]; do
      if [ "$_ufetched" = 0 ]; then                # first line is the fetch timestamp
        case "$_uname" in ''|*[!0-9]*) break ;; esac
        _ufetched="$_uname"
        [ $(( NOW - _ufetched )) -ge "$USAGE_MAX_AGE" ] && break
        continue
      fi
      case "${_upct:-}" in ''|*[!0-9]*) continue ;; esac
      _ulabel="${_uname%% *}"                      # "Fable 5" -> "Fable"
      _useg="${_ulabel} $(mk_bar "$_upct" 6) ${_upct}%"
      if [ "$_upct" -ge 80 ] 2>/dev/null; then
        _ueta=$(fmt_eta "${_ureset:-}")
        [ -n "$_ueta" ] && _useg="${_useg} ${ESC}[90m⟳ ${_ueta}${RESET}"
      fi
      _uparts+=("$_useg")
    done < "$STATE_DIR/usage-scoped"
    if [ "${#_uparts[@]}" -gt 0 ]; then
      mlim_seg="${_uparts[0]}"
      for ((_i=1; _i<${#_uparts[@]}; _i++)); do mlim_seg="${mlim_seg} ${_uparts[$_i]}"; done
    fi
  fi
fi

# --- Segment: Burn rate ($ per active hour) ---
burn_seg=""
[ -n "$burn_raw" ] && burn_seg="$(printf '$%.2f/h' "$burn_raw" 2>/dev/null)"

# --- Segment: Session cost (color escalates with spend) ---
cost_seg=""
if [ -n "$session_cost" ]; then
  cost_fmt="$(printf '$%.2f' "$session_cost" 2>/dev/null)"
  if [ "$SL_COST_COLOR" = 1 ] && [ -n "$cost_col" ]; then   # >=5 red, >=2 yellow, else dim
    cost_seg="${ESC}[${cost_col}m${cost_fmt}${RESET}"
  else
    cost_seg="$cost_fmt"
  fi
fi

# --- Segment: Session elapsed (wall-clock since first render this session) ---
# ⏱ is left bare: U+23F1 has Emoji_Presentation=Yes, so width calculators and the
# terminal already agree it is two columns. ⚠ (U+26A0) does not default to emoji
# presentation, which is why that one is pinned with U+FE0E.
elapsed_seg=""
if [ "$SL_ELAPSED" = 1 ] && [ -n "$session_id" ]; then
  mark="$STATE_DIR/${session_id}.start"
  if [ -f "$mark" ]; then
    read -r start < "$mark" 2>/dev/null
  else
    start=$NOW; printf '%s' "$NOW" > "$mark" 2>/dev/null
    # Prune only when a new session appears. A `find` on every render cost ~9ms and, at
    # -mtime +2, deleted the mark of any session still running after two days — which
    # restarted that session's clock at 0s.
    find "$STATE_DIR" -type f -name '*.start' -mtime +14 -delete 2>/dev/null
  fi
  case "${start:-}" in ''|*[!0-9]*) start=$NOW ;; esac
  el=$(( NOW - start )); [ "$el" -lt 0 ] && el=0
  if   [ "$el" -ge 3600 ]; then elapsed_seg="$(printf '⏱ %dh%02dm' "$(( el/3600 ))" "$(( (el%3600)/60 ))")"
  elif [ "$el" -ge 60   ]; then elapsed_seg="$(printf '⏱ %dm' "$(( el/60 ))")"
  else                          elapsed_seg="$(printf '⏱ %ds' "$el")"
  fi
fi

# --- Segment: Current time ---
time_seg="$CLOCK"

# --- Assemble with separators ---
SEP=" | "
parts=()

[ "$SL_DIRECTORY"    = 1 ]                           && parts+=("${dir_seg}")
[ "$SL_GIT"          = 1 ] && [ -n "$git_seg"      ] && parts+=("${git_seg}")
[ "$SL_MODEL"        = 1 ]                           && parts+=("${model_seg}")
[ "$SL_THINKING"     = 1 ] && [ -n "$thinking_seg" ] && parts+=("${thinking_seg}")
[ "$SL_EFFORT"       = 1 ] && [ -n "$effort_seg"   ] && parts+=("${effort_seg}")
[ "$SL_OUTPUTSTYLE"  = 1 ] && [ -n "$style_seg"    ] && parts+=("${style_seg}")
[ "$SL_CONTEXT"      = 1 ] && [ -n "$ctx_seg"      ] && parts+=("${ctx_seg}")
[ "$SL_TOKENS"       = 1 ] && [ -n "$tokens_seg"   ] && parts+=("${tokens_seg}")
[ "$SL_RATELIMIT_5H" = 1 ] && [ -n "$rl_seg"       ] && parts+=("${rl_seg}")
[ "$SL_RATELIMIT_7D" = 1 ] && [ -n "$rl7_seg"      ] && parts+=("${rl7_seg}")
[ "$SL_MODEL_LIMIT"  = 1 ] && [ -n "$mlim_seg"     ] && parts+=("${mlim_seg}")
[ "$SL_BURNRATE"     = 1 ] && [ -n "$burn_seg"     ] && parts+=("${burn_seg}")
[ "$SL_COST"         = 1 ] && [ -n "$cost_seg"     ] && parts+=("${cost_seg}")
[ "$SL_ELAPSED"      = 1 ] && [ -n "$elapsed_seg"  ] && parts+=("${elapsed_seg}")
[ "$SL_CLOCK"        = 1 ]                           && parts+=("${time_seg}")

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
