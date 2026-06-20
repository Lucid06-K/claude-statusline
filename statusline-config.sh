#!/usr/bin/env bash
# Interactive configurator for the Claude Code status line.
# Arrow-key driven (↑/↓ move, Enter select) in the same layout style as dsort.
# - Toggle elements, or apply/create/edit "modes" (presets) — all from the menu.
# - Saves immediately to ~/.claude/statusline.conf (read on every render).
# - Modes live in ~/.claude/statusline.modes (managed here, no file editing needed).

CONF="${HOME}/.claude/statusline.conf"
MODES="${HOME}/.claude/statusline.modes"
SL="${HOME}/.claude/statusline-command.sh"

ESC=$'\033'; R="${ESC}[0m"; B="${ESC}[1m"; DIM="${ESC}[2m"; REV="${ESC}[7m"
GRN="${ESC}[92m"; YEL="${ESC}[93m"; CYN="${ESC}[96m"; MAG="${ESC}[95m"
SEP="${DIM}──────────────────────────────────────────────────────────${R}"

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
state=(); tmp_state=(); ED=(); CURRENT_MODE=""; EDNAME=""; EDDESC=""
mode_names=(); mode_descs=(); mode_specs=()

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

# ---------- live config (toggle) load/save ----------
load() {
  local i; for ((i=0;i<n;i++)); do state[$i]=1; done
  CURRENT_MODE=""
  [ -f "$CONF" ] || return
  local k v
  while IFS='=' read -r k v; do
    case "$k" in ''|\#*) continue;; esac
    [ "$k" = "SL_MODE" ] && { CURRENT_MODE="$v"; continue; }
    for ((i=0;i<n;i++)); do [ "${keys[$i]}" = "$k" ] && state[$i]=$v; done
  done < "$CONF"
}
save() {
  { echo "# Claude Code status line — element toggles (1=show, 0=hide)"
    echo "# Managed by: bash ~/.claude/statusline-config.sh"
    echo "SL_MODE=${CURRENT_MODE}"
    local i; for ((i=0;i<n;i++)); do echo "${keys[$i]}=${state[$i]}"; done
  } > "$CONF"
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
spec_to_state() {
  local spec="$1" i first key
  for ((i=0;i<n;i++)); do tmp_state[$i]=0; done
  set -- $spec; first="$1"
  if [ "$first" = "ALL" ]; then for ((i=0;i<n;i++)); do tmp_state[$i]=1; done; return; fi
  { [ -z "$first" ] || [ "$first" = "NONE" ]; } && return
  for key in $spec; do
    for ((i=0;i<n;i++)); do [ "${keys[$i]}" = "$key" ] && tmp_state[$i]=1; done
  done
}
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
apply_mode() {
  spec_to_state "${mode_specs[$1]}"
  local i; for ((i=0;i<n;i++)); do state[$i]="${tmp_state[$i]}"; done
  CURRENT_MODE="${mode_names[$1]}"; save
}
delete_mode() {
  local nm="${mode_names[$1]}"; remove_mode_line "$nm"
  [ "$CURRENT_MODE" = "$nm" ] && CURRENT_MODE=""
  load_modes
}
mode_status() {
  [ -z "$CURRENT_MODE" ] && { echo "custom"; return; }
  local i mi=-1
  for ((i=0;i<${#mode_names[@]};i++)); do [ "${mode_names[$i]}" = "$CURRENT_MODE" ] && mi=$i; done
  [ "$mi" -lt 0 ] && { echo "$CURRENT_MODE"; return; }
  spec_to_state "${mode_specs[$mi]}"
  local diff=0; for ((i=0;i<n;i++)); do [ "${state[$i]}" != "${tmp_state[$i]}" ] && diff=1; done
  [ "$diff" = 1 ] && echo "${CURRENT_MODE} ${YEL}(modified)${R}" || echo "$CURRENT_MODE"
}

# ---------- preview ----------
render_sample() {
  local sid="preview-$$" r5 json; r5=$(( $(date +%s) + 2820 ))
  json=$(printf '{"session_id":"%s","cwd":"%s","effort":{"level":"xhigh"},"model":{"display_name":"Opus 4.8 (1M context)"},"workspace":{"current_dir":"%s"},"context_window":{"used_percentage":88},"fast_mode":true,"cost":{"total_cost_usd":6.40,"total_duration_ms":720000},"rate_limits":{"five_hour":{"used_percentage":100,"resets_at":%s},"seven_day":{"used_percentage":72,"resets_at":%s}}}' "$sid" "$HOME" "$HOME" "$r5" "$r5")
  if [ -n "$1" ]; then printf '%s' "$json" | SL_CONF="$1" COLORTERM="${COLORTERM:-truecolor}" bash "$SL"
  else                 printf '%s' "$json" |               COLORTERM="${COLORTERM:-truecolor}" bash "$SL"; fi
  rm -f "${TMPDIR:-/tmp}/cc-statusline/${sid}.start" 2>/dev/null
}
do_preview() { printf '\n  %sPreview%s %s(sample data: busy session)%s\n  ' "$B" "$R" "$DIM" "$R"; render_sample "$1"; printf '\n'; }

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

# ---------- mode editor ----------
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
  [ "$CURRENT_MODE" = "$oldname" ] && [ -n "$oldname" ] && CURRENT_MODE="$EDNAME"
  return 0
}
save_current_as_mode() {
  local nm ds i
  printf '%s' "${ESC}[?25h"
  read -rp "  New mode name (one word): " nm; nm="${nm// /}"
  [ -z "$nm" ] && { printf '%s' "${ESC}[?25l"; return; }
  read -rp "  Short description: " ds
  printf '%s' "${ESC}[?25l"
  for ((i=0;i<n;i++)); do ED[$i]="${state[$i]}"; done
  write_mode "$nm" "$ds" "$(ed_to_spec)"; CURRENT_MODE="$nm"; save
  printf '\n  %sSaved mode "%s".%s' "$GRN" "$nm" "$R"; anykey
}

# ---------- modes menu ----------
modes_menu() {
  local focus=0 key M nrows i
  printf '%s' "${ESC}[?25l"
  while :; do
    load_modes; M=${#mode_names[@]}; nrows=$((M+3))   # modes + New / Save current / Back
    [ "$focus" -ge "$nrows" ] && focus=$((nrows-1))
    printf '%s' "${ESC}[H${ESC}[2J"
    printf '\n  %sModes%s  %s— apply a preset, or create/edit one%s\n' "$B" "$R" "$DIM" "$R"
    printf '  active: %s\n' "$(mode_status)"
    printf '  %s\n' "$SEP"
    for ((i=0;i<M;i++)); do
      local star="  "; [ "${mode_names[$i]}" = "$CURRENT_MODE" ] && star="${GRN}●${R} "
      if [ "$focus" -eq "$i" ]; then
        printf '  %s ▸ %-10s %s %s\n' "$REV" "${mode_names[$i]}" "${mode_descs[$i]}" "$R"
      else
        printf '   %s%s%-10s%s %s%s%s\n' "$star" "$CYN" "${mode_names[$i]}" "$R" "$DIM" "${mode_descs[$i]}" "$R"
      fi
    done
    printf '  %s\n' "$SEP"
    row_action "+ Create new mode"    "$([ "$focus" -eq "$M" ] && echo 1 || echo 0)"
    row_action "Save current as mode" "$([ "$focus" -eq $((M+1)) ] && echo 1 || echo 0)"
    row_action "← Back"               "$([ "$focus" -eq $((M+2)) ] && echo 1 || echo 0)"
    printf '\n  %s↑/↓ move · enter apply/select · e edit · d delete · p preview · esc back%s\n' "$DIM" "$R"
    key=$(read_key)
    case "$key" in
      up|k)    focus=$(( (focus+nrows-1)%nrows )) ;;
      down|j)  focus=$(( (focus+1)%nrows )) ;;
      esc|b|B) return ;;
      e|E)     [ "$focus" -lt "$M" ] && edit_mode "$focus" ;;
      d|D)     [ "$focus" -lt "$M" ] && delete_mode "$focus" ;;
      c|C)     edit_mode "" ;;
      s|S)     save_current_as_mode ;;
      p|P)     do_preview; anykey ;;
      "")      if   [ "$focus" -lt "$M" ]; then apply_mode "$focus"; do_preview; anykey
               elif [ "$focus" -eq "$M" ]; then edit_mode ""
               elif [ "$focus" -eq $((M+1)) ]; then save_current_as_mode
               else return; fi ;;
    esac
  done
}

# ---------- main menu ----------
finish() {
  save; printf '%s' "${ESC}[?25h${ESC}[H${ESC}[2J"
  printf '\n  %sSaved.%s Status line updated — it refreshes automatically.\n' "$GRN" "$R"
  do_preview; printf '\n'
  exit 0
}
main_menu() {
  local focus=0 key i nrows; nrows=$((n+4))   # elements + Modes / All on / All off / Save & quit
  printf '%s' "${ESC}[?25l"
  while :; do
    load_modes
    printf '%s' "${ESC}[H${ESC}[2J"
    printf '\n  %sClaude Code status line%s  %s— choose what shows%s\n' "$B" "$R" "$DIM" "$R"
    printf '  mode: %s\n' "$(mode_status)"
    printf '  %s\n' "$SEP"
    for ((i=0;i<n;i++)); do row_toggle "$i" "${state[$i]}" "$([ "$focus" -eq "$i" ] && echo 1 || echo 0)"; done
    printf '  %s\n' "$SEP"
    row_action "Modes (presets) ▸" "$([ "$focus" -eq "$n" ] && echo 1 || echo 0)"
    row_action "Turn all on"       "$([ "$focus" -eq $((n+1)) ] && echo 1 || echo 0)"
    row_action "Turn all off"      "$([ "$focus" -eq $((n+2)) ] && echo 1 || echo 0)"
    row_action "${GRN}Save & quit${R}" "$([ "$focus" -eq $((n+3)) ] && echo 1 || echo 0)"
    printf '\n  %s↑/↓ move · enter toggle/select · m modes · ? explain · p preview · q quit%s\n' "$DIM" "$R"
    key=$(read_key)
    case "$key" in
      up|k)    focus=$(( (focus+nrows-1)%nrows )) ;;
      down|j)  focus=$(( (focus+1)%nrows )) ;;
      q|Q|esc) finish ;;
      m|M)     modes_menu ;;
      p|P)     do_preview; anykey ;;
      a|A)     for ((i=0;i<n;i++)); do state[$i]=1; done; save ;;
      \?)      if [ "$focus" -lt "$n" ]; then
                 printf '%s' "${ESC}[H${ESC}[2J"
                 printf '\n  %s%s%s — %s%s%s\n\n  %s\n' "$B" "${labels[$focus]}" "$R" "$DIM" "${shorts[$focus]}" "$R" "${longs[$focus]}"
                 anykey
               fi ;;
      "")      if   [ "$focus" -lt "$n" ]; then [ "${state[$focus]}" = 1 ] && state[$focus]=0 || state[$focus]=1; save
               elif [ "$focus" -eq "$n" ]; then modes_menu
               elif [ "$focus" -eq $((n+1)) ]; then for ((i=0;i<n;i++)); do state[$i]=1; done; save
               elif [ "$focus" -eq $((n+2)) ]; then for ((i=0;i<n;i++)); do state[$i]=0; done; save
               else finish; fi ;;
    esac
  done
}

seed_modes; load; main_menu
