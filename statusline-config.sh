#!/usr/bin/env bash
# Mode manager for the Claude Code status line (arrow-key TUI, dsort layout).
# - Main screen lists MODES (presets). Enter sets the highlighted mode as the
#   DEFAULT for new sessions (writes ~/.claude/statusline.conf).
# - e = edit / c = create opens the element editor (individual on/off lives there).
# - Per-session selection happens inside Claude with the /mode command.
# - Modes are stored in ~/.claude/statusline.modes (managed here, no file editing).

CONF="${HOME}/.claude/statusline.conf"
MODES="${HOME}/.claude/statusline.modes"
PICKER="${HOME}/.claude/statusline.picker"
SL="${HOME}/.claude/statusline-command.sh"

ESC=$'\033'; R="${ESC}[0m"; B="${ESC}[1m"; DIM="${ESC}[2m"; REV="${ESC}[7m"
GRN="${ESC}[92m"; YEL="${ESC}[93m"; CYN="${ESC}[96m"; MAG="${ESC}[95m"; RED="${ESC}[91m"
ORANGE="${ESC}[38;2;215;119;87m"
SEP="${DIM}──────────────────────────────────────────────────────────${R}"

# mini coloured bar (matches the status line's mk_bar) — used by the per-element previews
mini_bar() {
  local pct=$1 width=${2:-6} filled empty col f="" e="" i
  filled=$(( (pct*width+50)/100 )); [ "$filled" -gt "$width" ] && filled=$width; [ "$filled" -lt 0 ] && filled=0
  empty=$(( width-filled ))
  if [ "$pct" -ge 80 ]; then col=91; elif [ "$pct" -ge 50 ]; then col=93; else col=92; fi
  for ((i=0;i<filled;i++)); do f+="█"; done
  for ((i=0;i<empty;i++)); do e+="░"; done
  printf '%s[90m▕%s[%dm%s%s[90m%s▏%s' "$ESC" "$ESC" "$col" "$f" "$ESC" "$e" "$R"
}

cleanup() { printf '%s' "${ESC}[?25h"; }   # always restore the cursor
trap cleanup EXIT INT TERM

# key | label | one-line summary | full explanation
keys=(   SL_DIRECTORY SL_GIT SL_MODEL SL_FASTMODE SL_EFFORT SL_CONTEXT SL_CONTEXT_WARN \
         SL_RATELIMIT_5H SL_RATELIMIT_7D SL_BURNRATE SL_COST SL_COST_COLOR SL_ELAPSED SL_CLOCK )
labels=( "Directory" "Git status" "Model name" "Fast-mode flag" "Reasoning effort" \
         "Context meter" "Context warning" "5-hour limit" "7-day limit" "Burn rate" \
         "Session cost" "Cost color" "Session timer" "Clock" )
shorts=( "current folder (📁 ~/…)" \
         "branch, dirty *, ahead/behind ⇡⇣" \
         "model name in Claude orange" \
         "⚡ when /fast is on" \
         "reasoning effort, colored like the selector" \
         "context-window bar + %" \
         "⚠ when context is near auto-compact" \
         "rolling 5-hour usage meter" \
         "rolling 7-day usage meter (when high)" \
         "spend rate, \$ per active hour" \
         "total \$ spent this session" \
         "tint the \$ as spend climbs" \
         "⏱ time since session start" \
         "current time of day" )
longs=(  "The working directory. Home shows as ~, a folder directly under home as ~/name, and anything deeper as the last two path segments (e.g. Projects/petpak)." \
         "When inside a git repo: the branch, a * if there are uncommitted changes, and ⇡N/⇣N for commits ahead of / behind upstream. Hidden outside repos; turning it off also skips the git calls (slightly faster)." \
         "The active model's display name (e.g. Opus 4.8 (1M context)) in Claude's brand orange." \
         "A ⚡ next to the model only while fast mode (/fast) is active." \
         "Your reasoning-effort level (low/medium/high/xhigh/max), colored to match Claude Code's own effort selector: yellow / green / blue / magenta / rainbow." \
         "A 10-cell bar + percentage of how full the context window is, shifting green → yellow → red as it fills." \
         "A red ⚠ on the context meter once usage passes 85% — i.e. you're close to an automatic /compact." \
         "How much of your plan's rolling 5-hour allowance is spent (bar + %). At ≥80% it shows a ⟳ reset countdown. Hitting 100% is what triggers 'Now using usage credits'." \
         "Same meter for the rolling 7-day window. Hidden until 50% so it only shows when it matters; reset countdown at ≥80%." \
         "Spend velocity: dollars per hour of active processing time (cost ÷ active duration)." \
         "Total dollars spent in this session so far." \
         "Tints the cost figure with spend: dim under \$2, yellow at ≥\$2, red at ≥\$5. Off = plain text." \
         "A ⏱ timer counting wall-clock time since the session began (via a small marker file, auto-cleaned after 2 days)." \
         "The current clock time (HH:MM)." )

n=${#keys[@]}
tmp_state=(); ED=(); CURRENT_MODE=""; EDNAME=""; EDDESC=""
mode_names=(); mode_descs=(); mode_specs=()

# Per-element example renders — shown for whichever option the editor selector sits on.
prev=()
prev[0]="📁 Projects/petpak"
prev[1]="feat/vet ${GRN}⇡2${R}"
prev[2]="${ORANGE}Opus 4.8${R}"
prev[3]="${ORANGE}Opus 4.8${R} ${YEL}⚡${R}"
prev[4]="${MAG}xhigh${R}"
prev[5]="$(mini_bar 42 10) 42%"
prev[6]="$(mini_bar 88 10) 88% ${RED}⚠${R}"
prev[7]="5h $(mini_bar 62 6) 62% ${DIM}⟳ 2h35m${R}"
prev[8]="7d $(mini_bar 72 6) 72%"
prev[9]="\$11.20/h"
prev[10]="\$6.40"
prev[11]="${RED}\$6.40${R}"
prev[12]="⏱ 12m"
prev[13]="19:02"

# ---------- one keypress -> token (up/down/esc / "" for enter / literal char) ----------
read_key() {
  local k rest
  IFS= read -r -s -n 1 k || { printf esc; return; }   # EOF (e.g. closed stdin) -> unwind cleanly
  if [ "$k" = $'\033' ]; then
    IFS= read -r -s -n 2 -t 1 rest 2>/dev/null
    case "$rest" in '[A') printf up;; '[B') printf down;; *) printf esc;; esac
  else printf '%s' "$k"; fi
}
anykey() { printf '\n  %spress any key%s' "$DIM" "$R"; IFS= read -r -s -n 1 _ 2>/dev/null; }

# ---------- global default (the conf the status line reads for new sessions) ----------
read_default_mode() {            # -> CURRENT_MODE from the global conf's SL_MODE
  CURRENT_MODE=""
  [ -f "$CONF" ] || return
  local k v
  while IFS='=' read -r k v; do [ "$k" = "SL_MODE" ] && { CURRENT_MODE="$v"; return; }; done < "$CONF"
}
write_default() {                # $1 = mode name, $2.. via spec_to_state already in tmp_state
  { echo "# Claude Code status line — global default for new sessions (managed by slconfig)"
    echo "SL_MODE=$1"
    local i; for ((i=0;i<n;i++)); do echo "${keys[$i]}=${tmp_state[$i]}"; done
  } > "$CONF"
  CURRENT_MODE="$1"
}

# ---------- modes ----------
seed_modes() {
  [ -f "$MODES" ] && return
  cat > "$MODES" <<'EOF'
# Claude Code status line — modes (presets). Managed via the configurator menu.
# format:  name|description|ON-keys (space separated; ALL = everything, NONE = nothing)
full|Everything on|ALL
work|Coding essentials — path, git, model, effort, context|SL_DIRECTORY SL_GIT SL_MODEL SL_FASTMODE SL_EFFORT SL_CONTEXT SL_CONTEXT_WARN SL_CLOCK
cost|Watch spend & rate limits|SL_DIRECTORY SL_MODEL SL_RATELIMIT_5H SL_RATELIMIT_7D SL_BURNRATE SL_COST SL_COST_COLOR SL_CLOCK
minimal|Path, git, model, clock|SL_DIRECTORY SL_GIT SL_MODEL SL_CLOCK
focus|Just enough to stay oriented|SL_DIRECTORY SL_MODEL SL_EFFORT
zen|Nothing — a clean, empty line|NONE
EOF
}
load_modes() {
  mode_names=(); mode_descs=(); mode_specs=()
  [ -f "$MODES" ] || return
  local nm ds sp
  while IFS='|' read -r nm ds sp; do
    case "$nm" in ''|\#*) continue;; esac
    nm="${nm// /}"; ds="${ds# }"
    mode_names+=("$nm"); mode_descs+=("$ds"); mode_specs+=("$sp")
  done < "$MODES"
}
spec_to_state() {                # fill tmp_state[] from a spec string
  local spec="$1" i first key
  for ((i=0;i<n;i++)); do tmp_state[$i]=0; done
  set -- $spec; first="$1"
  if [ "$first" = "ALL" ]; then for ((i=0;i<n;i++)); do tmp_state[$i]=1; done; return; fi
  { [ -z "$first" ] || [ "$first" = "NONE" ]; } && return
  for key in $spec; do
    for ((i=0;i<n;i++)); do [ "${keys[$i]}" = "$key" ] && tmp_state[$i]=1; done
  done
}
spec_to_conf() { spec_to_state "$1"; local i; for ((i=0;i<n;i++)); do echo "${keys[$i]}=${tmp_state[$i]}"; done; }
ed_to_spec() {
  local i on="" allon=1 alloff=1
  for ((i=0;i<n;i++)); do
    if [ "${ED[$i]}" = 1 ]; then on="$on ${keys[$i]}"; alloff=0; else allon=0; fi
  done
  if   [ "$allon"  = 1 ]; then echo "ALL"
  elif [ "$alloff" = 1 ]; then echo "NONE"
  else echo "${on# }"; fi
}
remove_mode_line() { seed_modes; local tmp="${MODES}.tmp"; grep -v "^${1}|" "$MODES" > "$tmp" 2>/dev/null; mv -f "$tmp" "$MODES"; }
write_mode() { remove_mode_line "$1"; printf '%s|%s|%s\n' "$1" "$2" "$3" >> "$MODES"; load_modes; }
set_default() {                  # $1 = mode index -> make it the new-session default
  spec_to_state "${mode_specs[$1]}"; write_default "${mode_names[$1]}"
}
delete_mode() {
  local nm="${mode_names[$1]}"; remove_mode_line "$nm"
  [ "$CURRENT_MODE" = "$nm" ] && CURRENT_MODE=""
  picker=( $(printf '%s\n' "${picker[@]}" | grep -vxF -- "$nm") ); save_picker
  load_modes
}

# ---------- /mode picker selection (which modes appear in the in-Claude /mode picker) ----------
picker=()
load_picker() {
  picker=()
  if [ -f "$PICKER" ]; then
    local line; while IFS= read -r line; do [ -n "$line" ] && picker+=("$line"); done < "$PICKER"
  else
    local i; for ((i=0;i<${#mode_names[@]} && i<4;i++)); do picker+=("${mode_names[$i]}"); done
    save_picker
  fi
}
in_picker() { local x; for x in "${picker[@]}"; do [ "$x" = "$1" ] && return 0; done; return 1; }
save_picker() { : > "$PICKER"; local x; for x in "${picker[@]}"; do printf '%s\n' "$x" >> "$PICKER"; done; }
toggle_picker() {                # $1 = mode name; returns 1 if blocked by the 4-item cap
  if in_picker "$1"; then
    local new=() x; for x in "${picker[@]}"; do [ "$x" != "$1" ] && new+=("$x"); done; picker=("${new[@]}"); save_picker; return 0
  fi
  [ "${#picker[@]}" -ge 4 ] && return 1
  picker+=("$1"); save_picker; return 0
}

# ---------- preview ----------
render_sample() {                # $1 = optional conf path. Runs in an isolated TMPDIR so it
  local sid="preview-$$" r5 json td  #     never touches the real session timer / rate-limit cache.
  r5=$(( $(date +%s) + 2820 )); td="$(mktemp -d 2>/dev/null)"
  json=$(printf '{"session_id":"%s","cwd":"%s","effort":{"level":"xhigh"},"model":{"display_name":"Opus 4.8 (1M context)"},"workspace":{"current_dir":"%s"},"context_window":{"used_percentage":88},"fast_mode":true,"cost":{"total_cost_usd":6.40,"total_duration_ms":720000},"rate_limits":{"five_hour":{"used_percentage":100,"resets_at":%s},"seven_day":{"used_percentage":72,"resets_at":%s}}}' "$sid" "$HOME" "$HOME" "$r5" "$r5")
  if [ -n "$1" ]; then printf '%s' "$json" | TMPDIR="$td" SL_CONF="$1" COLORTERM="${COLORTERM:-truecolor}" bash "$SL"
  else                 printf '%s' "$json" | TMPDIR="$td"               COLORTERM="${COLORTERM:-truecolor}" bash "$SL"; fi
  rm -rf "$td" 2>/dev/null
}
do_preview() { printf '\n  %sPreview%s %s(sample data: busy session)%s\n  ' "$B" "$R" "$DIM" "$R"; render_sample "$1"; printf '\n'; }
preview_spec() { local tc; tc="$(mktemp)"; spec_to_conf "$1" > "$tc"; render_sample "$tc"; rm -f "$tc"; }

# ---------- row renderers (dsort style: ▸ + reverse-video on focus) ----------
row_toggle() {   # $1 idx  $2 on/off  $3 focus?
  local i="$1" on="$2" foc="$3" chk
  [ "$on" = 1 ] && chk="✓" || chk=" "
  if [ "$foc" = 1 ]; then
    printf '  %s ▸ [%s] %-16s %s %s\n' "$REV" "$chk" "${labels[$i]}" "${shorts[$i]}" "$R"
  else
    local g=" "; [ "$on" = 1 ] && g="${GRN}✓${R}"
    printf '     [%s] %-16s %s%s%s\n' "$g" "${labels[$i]}" "$DIM" "${shorts[$i]}" "$R"
  fi
}
row_action() {   # $1 text  $2 focus?
  if [ "$2" = 1 ]; then printf '  %s ▸ %s %s\n' "$REV" "$1" "$R"
  else printf '     %s\n' "$1"; fi
}

# ---------- mode editor (where individual on/off lives) ----------
edit_mode() {            # $1 = index to edit, or "" to create new
  local i idx="$1" oldname="" focus=0 nrows key v
  if [ -n "$idx" ]; then
    EDNAME="${mode_names[$idx]}"; EDDESC="${mode_descs[$idx]}"; oldname="$EDNAME"
    spec_to_state "${mode_specs[$idx]}"
  else
    EDNAME=""; EDDESC=""; for ((i=0;i<n;i++)); do tmp_state[$i]=0; done
  fi
  for ((i=0;i<n;i++)); do ED[$i]="${tmp_state[$i]}"; done
  nrows=$((n+4))                       # elements + Rename / Description / Save / Cancel
  printf '%s' "${ESC}[?25l"
  while :; do
    printf '%s' "${ESC}[H${ESC}[2J"
    printf '\n  %s%s%s  %s— toggle what this mode includes%s\n' "$B" "$([ -n "$oldname" ] && echo "Edit mode" || echo "New mode")" "$R" "$DIM" "$R"
    printf '  name %s%s%s   desc %s%s%s\n' "$CYN" "${EDNAME:-<unset>}" "$R" "$DIM" "${EDDESC:-<none>}" "$R"
    printf '  %s\n' "$SEP"
    for ((i=0;i<n;i++)); do row_toggle "$i" "${ED[$i]}" "$([ "$focus" -eq "$i" ] && echo 1 || echo 0)"; done
    printf '  %s\n' "$SEP"
    row_action "Rename"           "$([ "$focus" -eq "$n" ] && echo 1 || echo 0)"
    row_action "Edit description" "$([ "$focus" -eq $((n+1)) ] && echo 1 || echo 0)"
    row_action "${GRN}Save mode${R}" "$([ "$focus" -eq $((n+2)) ] && echo 1 || echo 0)"
    row_action "Cancel"           "$([ "$focus" -eq $((n+3)) ] && echo 1 || echo 0)"
    local pv tc2
    if [ "$focus" -lt "$n" ]; then pv="${prev[$focus]}"
    else tc2="$(mktemp)"; for ((i=0;i<n;i++)); do echo "${keys[$i]}=${ED[$i]}"; done > "$tc2"; pv="$(render_sample "$tc2")"; rm -f "$tc2"; fi
    printf '  %s\n' "$SEP"
    printf '  %srender%s  %s\n' "$DIM" "$R" "$pv"
    printf '\n  %s↑/↓ move · enter toggle/select · r rename · t desc · p preview · s save · esc cancel%s\n' "$DIM" "$R"
    key=$(read_key)
    case "$key" in
      up|k)   focus=$(( (focus+nrows-1)%nrows )) ;;
      down|j) focus=$(( (focus+1)%nrows )) ;;
      esc)    return ;;
      r|R)    printf '%s' "${ESC}[?25h"; read -rp "  Name (one word): " v; v="${v// /}"; [ -n "$v" ] && EDNAME="$v"; printf '%s' "${ESC}[?25l" ;;
      t|T)    printf '%s' "${ESC}[?25h"; read -rp "  Description: " v; EDDESC="$v"; printf '%s' "${ESC}[?25l" ;;
      p|P)    local tc; tc="$(mktemp)"; for ((i=0;i<n;i++)); do echo "${keys[$i]}=${ED[$i]}"; done > "$tc"; do_preview "$tc"; rm -f "$tc"; anykey ;;
      s|S)    edit_save "$oldname" && return ;;
      "")     if [ "$focus" -lt "$n" ]; then
                [ "${ED[$focus]}" = 1 ] && ED[$focus]=0 || ED[$focus]=1
              elif [ "$focus" -eq "$n" ]; then printf '%s' "${ESC}[?25h"; read -rp "  Name (one word): " v; v="${v// /}"; [ -n "$v" ] && EDNAME="$v"; printf '%s' "${ESC}[?25l"
              elif [ "$focus" -eq $((n+1)) ]; then printf '%s' "${ESC}[?25h"; read -rp "  Description: " v; EDDESC="$v"; printf '%s' "${ESC}[?25l"
              elif [ "$focus" -eq $((n+2)) ]; then edit_save "$oldname" && return
              else return; fi ;;
    esac
  done
}
edit_save() {            # $1 = oldname; returns 0 to close editor
  local oldname="$1"
  if [ -z "$EDNAME" ]; then printf '%s' "${ESC}[?25h"; read -rp "  Name this mode (one word): " EDNAME; EDNAME="${EDNAME// /}"; printf '%s' "${ESC}[?25l"; fi
  [ -z "$EDNAME" ] && { printf '\n  %sName required.%s' "$YEL" "$R"; anykey; return 1; }
  [ -n "$oldname" ] && [ "$oldname" != "$EDNAME" ] && remove_mode_line "$oldname"
  write_mode "$EDNAME" "$EDDESC" "$(ed_to_spec)"
  [ -n "$oldname" ] && [ "$CURRENT_MODE" = "$oldname" ] && CURRENT_MODE="$EDNAME"
  # if we edited the current default, refresh the global conf so it stays in sync
  if [ "$EDNAME" = "$CURRENT_MODE" ]; then
    local j; for ((j=0;j<${#mode_names[@]};j++)); do [ "${mode_names[$j]}" = "$EDNAME" ] && { set_default "$j"; break; }; done
  fi
  return 0
}

# ---------- main menu: pick the default mode for new sessions ----------
finish() {
  printf '%s' "${ESC}[?25h${ESC}[H${ESC}[2J"
  printf '\n  %sDone.%s Default for new sessions: %s%s%s\n' "$GRN" "$R" "$CYN" "${CURRENT_MODE:-custom}" "$R"
  printf '  %sthis session, switch anytime with%s %s/mode <name>%s\n' "$DIM" "$R" "$CYN" "$R"
  do_preview; printf '\n'
  exit 0
}
# Choose which modes appear in the in-Claude /mode picker (up to 4).
picker_menu() {
  local focus=0 key M i msg=""
  printf '%s' "${ESC}[?25l"
  while :; do
    load_modes; M=${#mode_names[@]}
    [ "$M" -eq 0 ] && return
    [ "$focus" -ge "$M" ] && focus=$((M-1)); [ "$focus" -lt 0 ] && focus=0
    printf '%s' "${ESC}[H${ESC}[2J"
    printf '\n  %sChoose what appears in /mode%s  %s(the in-Claude picker, up to 4)%s\n' "$B" "$R" "$DIM" "$R"
    printf '  selected: %s%d/4%s\n' "$CYN" "${#picker[@]}" "$R"
    [ -n "$msg" ] && printf '  %s%s%s\n' "$YEL" "$msg" "$R"
    printf '  %s\n' "$SEP"
    for ((i=0;i<M;i++)); do
      local chk=" "; in_picker "${mode_names[$i]}" && chk="✓"
      if [ "$focus" -eq "$i" ]; then
        printf '  %s ▸ [%s] %-10s %s %s\n' "$REV" "$chk" "${mode_names[$i]}" "${mode_descs[$i]}" "$R"
      else
        local g=" "; [ "$chk" = "✓" ] && g="${GRN}✓${R}"
        printf '     [%s] %s%-10s%s %s%s%s\n' "$g" "$CYN" "${mode_names[$i]}" "$R" "$DIM" "${mode_descs[$i]}" "$R"
      fi
    done
    printf '  %s\n' "$SEP"
    printf '\n  %s↑/↓ move · space/enter toggle · esc done%s\n' "$DIM" "$R"
    key=$(read_key)
    case "$key" in
      up|k)        focus=$(( (focus+M-1)%M )); msg="" ;;
      down|j)      focus=$(( (focus+1)%M )); msg="" ;;
      esc|b|B|q|Q) return ;;
      " "|"")      if toggle_picker "${mode_names[$focus]}"; then msg=""; else msg="picker is full (4) — uncheck one first"; fi ;;
    esac
  done
}
main_menu() {
  local focus=0 key M nrows i MSG=""
  printf '%s' "${ESC}[?25l"
  while :; do
    read_default_mode; load_modes
    M=${#mode_names[@]}; nrows=$((M+3))            # modes + Configure picker + Create + Quit
    [ "$focus" -ge "$nrows" ] && focus=$((nrows-1)); [ "$focus" -lt 0 ] && focus=0
    printf '%s' "${ESC}[H${ESC}[2J"
    printf '\n  %sClaude Code status line — Modes%s\n' "$B" "$R"
    printf '  %sdefault for new sessions:%s %s%s%s   %s★ default · ·/mode = in picker%s\n' "$DIM" "$R" "$CYN" "${CURRENT_MODE:-custom}" "$R" "$DIM" "$R"
    [ -n "$MSG" ] && printf '  %s%s%s\n' "$GRN" "$MSG" "$R"
    printf '  %s\n' "$SEP"
    for ((i=0;i<M;i++)); do
      local star="  "; [ "${mode_names[$i]}" = "$CURRENT_MODE" ] && star="${GRN}★${R} "
      if [ "$focus" -eq "$i" ]; then
        local pt=""; in_picker "${mode_names[$i]}" && pt="  ·/mode"
        printf '  %s ▸ %-10s %s%s %s\n' "$REV" "${mode_names[$i]}" "${mode_descs[$i]}" "$pt" "$R"
      else
        local pt=""; in_picker "${mode_names[$i]}" && pt=" ${DIM}·/mode${R}"
        printf '   %s%s%-10s%s %s%s%s%s\n' "$star" "$CYN" "${mode_names[$i]}" "$R" "$DIM" "${mode_descs[$i]}" "$R" "$pt"
      fi
    done
    printf '  %s\n' "$SEP"
    row_action "Configure /mode picker ▸" "$([ "$focus" -eq "$M" ] && echo 1 || echo 0)"
    row_action "+ Create new mode"        "$([ "$focus" -eq $((M+1)) ] && echo 1 || echo 0)"
    row_action "${GRN}Quit${R}"           "$([ "$focus" -eq $((M+2)) ] && echo 1 || echo 0)"
    local pv=""; [ "$focus" -lt "$M" ] && pv="$(preview_spec "${mode_specs[$focus]}")"
    printf '  %s\n' "$SEP"
    printf '  %srender%s  %s\n' "$DIM" "$R" "$pv"
    printf '\n  %s↑/↓ move · enter set default · g /mode picker · e edit · c new · d delete · p preview · q quit%s\n' "$DIM" "$R"
    key=$(read_key)
    case "$key" in
      up|k)    focus=$(( (focus+nrows-1)%nrows )); MSG="" ;;
      down|j)  focus=$(( (focus+1)%nrows )); MSG="" ;;
      q|Q|esc) finish ;;
      g|G)     picker_menu ;;
      e|E)     [ "$focus" -lt "$M" ] && edit_mode "$focus" ;;
      c|C)     edit_mode "" ;;
      d|D)     if [ "$focus" -lt "$M" ]; then local dn="${mode_names[$focus]}"; delete_mode "$focus"; MSG="deleted '$dn'"; fi ;;
      p|P)     if [ "$focus" -lt "$M" ]; then printf '\n  '; preview_spec "${mode_specs[$focus]}"; anykey; fi ;;
      "")      if   [ "$focus" -lt "$M" ]; then set_default "$focus"; MSG="★ '${CURRENT_MODE}' is now the default for new sessions"
               elif [ "$focus" -eq "$M" ]; then picker_menu
               elif [ "$focus" -eq $((M+1)) ]; then edit_mode ""
               else finish; fi ;;
    esac
  done
}

seed_modes; load_modes; load_picker; main_menu
