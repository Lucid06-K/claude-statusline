#!/usr/bin/env bash
# Interactive configurator for the Claude Code status line.
# - Toggle individual elements, or apply a "mode" (named preset).
# - Create/edit/rename/delete modes entirely from the menu.
# - Changes save immediately to ~/.claude/statusline.conf (read on every render).
# - Modes are stored in ~/.claude/statusline.modes (managed via this menu).

CONF="${HOME}/.claude/statusline.conf"
MODES="${HOME}/.claude/statusline.modes"
SL="${HOME}/.claude/statusline-command.sh"

ESC=$'\033'; B="${ESC}[1m"; DIM="${ESC}[90m"; GRN="${ESC}[92m"; YEL="${ESC}[93m"
CYN="${ESC}[96m"; MAG="${ESC}[95m"; R="${ESC}[0m"

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
         "⏱ wall-clock time since session start" \
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
spec_to_state() {            # fill tmp_state[] from a spec string
  local spec="$1" i first key
  for ((i=0;i<n;i++)); do tmp_state[$i]=0; done
  set -- $spec; first="$1"
  if [ "$first" = "ALL" ]; then for ((i=0;i<n;i++)); do tmp_state[$i]=1; done; return; fi
  { [ -z "$first" ] || [ "$first" = "NONE" ]; } && return
  for key in $spec; do
    for ((i=0;i<n;i++)); do [ "${keys[$i]}" = "$key" ] && tmp_state[$i]=1; done
  done
}
ed_to_spec() {               # build a spec string from ED[]
  local i on="" allon=1 alloff=1
  for ((i=0;i<n;i++)); do
    if [ "${ED[$i]}" = 1 ]; then on="$on ${keys[$i]}"; alloff=0; else allon=0; fi
  done
  if   [ "$allon"  = 1 ]; then echo "ALL"
  elif [ "$alloff" = 1 ]; then echo "NONE"
  else echo "${on# }"; fi
}
remove_mode_line() {         # delete a mode by name from the file
  seed_modes; local tmp="${MODES}.tmp"
  grep -v "^${1}|" "$MODES" > "$tmp" 2>/dev/null; mv -f "$tmp" "$MODES"
}
write_mode() {               # $1 name  $2 desc  $3 spec  (replace-or-append)
  remove_mode_line "$1"
  printf '%s|%s|%s\n' "$1" "$2" "$3" >> "$MODES"
  load_modes
}
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
mode_status() {              # active mode name, "(modified)" if toggles diverge, else "custom"
  [ -z "$CURRENT_MODE" ] && { echo "custom"; return; }
  local i mi=-1
  for ((i=0;i<${#mode_names[@]};i++)); do [ "${mode_names[$i]}" = "$CURRENT_MODE" ] && mi=$i; done
  [ "$mi" -lt 0 ] && { echo "$CURRENT_MODE"; return; }
  spec_to_state "${mode_specs[$mi]}"
  local diff=0; for ((i=0;i<n;i++)); do [ "${state[$i]}" != "${tmp_state[$i]}" ] && diff=1; done
  [ "$diff" = 1 ] && echo "${CURRENT_MODE} (modified)" || echo "$CURRENT_MODE"
}

# ---------- preview ----------
render_sample() {            # $1 = optional conf path to render with
  local sid="preview-$$" r5 json; r5=$(( $(date +%s) + 2820 ))
  json=$(printf '{"session_id":"%s","cwd":"%s","effort":{"level":"xhigh"},"model":{"display_name":"Opus 4.8 (1M context)"},"workspace":{"current_dir":"%s"},"context_window":{"used_percentage":88},"fast_mode":true,"cost":{"total_cost_usd":6.40,"total_duration_ms":720000},"rate_limits":{"five_hour":{"used_percentage":100,"resets_at":%s},"seven_day":{"used_percentage":72,"resets_at":%s}}}' "$sid" "$HOME" "$HOME" "$r5" "$r5")
  if [ -n "$1" ]; then printf '%s' "$json" | SL_CONF="$1" COLORTERM="${COLORTERM:-truecolor}" bash "$SL"
  else                 printf '%s' "$json" |               COLORTERM="${COLORTERM:-truecolor}" bash "$SL"; fi
  rm -f "${TMPDIR:-/tmp}/cc-statusline/${sid}.start" 2>/dev/null
}
do_preview() { printf '\n%sPreview%s %s(sample data: busy session)%s\n  ' "$B" "$R" "$DIM" "$R"; render_sample "$1"; printf '\n'; }
pause() { printf '%s' "$DIM"; read -rp "  (press enter) " _; printf '%s' "$R"; }

# ---------- mode editor (in-menu, no file editing) ----------
edit_mode() {                # $1 = index to edit, or "" to create new
  local i idx="$1" oldname="" box col v line tok j
  if [ -n "$idx" ]; then
    EDNAME="${mode_names[$idx]}"; EDDESC="${mode_descs[$idx]}"; oldname="$EDNAME"
    spec_to_state "${mode_specs[$idx]}"
  else
    EDNAME=""; EDDESC=""
    for ((i=0;i<n;i++)); do tmp_state[$i]=0; done
  fi
  for ((i=0;i<n;i++)); do ED[$i]="${tmp_state[$i]}"; done
  while true; do
    clear
    printf '%s┌─ %s ──────────────────────────────────────┐%s\n' "$YEL" "$([ -n "$oldname" ] && echo "Edit mode" || echo "New mode")" "$R"
    printf '  %sname%s %s%s%s    %sdesc%s %s%s%s\n\n' "$B" "$R" "$CYN" "${EDNAME:-<unset>}" "$R" "$B" "$R" "$DIM" "${EDDESC:-<none>}" "$R"
    for ((i=0;i<n;i++)); do
      if [ "${ED[$i]}" = 1 ]; then box="${GRN}[✓]${R}"; col=""; else box="${DIM}[ ]${R}"; col="$DIM"; fi
      printf "  %s%2d.%s %s %s%-17s%s %s%s%s\n" "$B" "$((i+1))" "$R" "$box" "$col" "${labels[$i]}" "$R" "$DIM" "${shorts[$i]}" "$R"
    done
    printf '\n%scommands%s  number(s)=toggle  r=rename  t=edit description  p=preview  s=save  b=cancel\n' "$B" "$R"
    read -rp $'\n> ' line
    case "$line" in
      b|B) return ;;
      r|R) read -rp "  Name (one word): " v; v="${v// /}"; [ -n "$v" ] && EDNAME="$v" ;;
      t|T) read -rp "  Description: " v; EDDESC="$v" ;;
      p|P) local tc; tc="$(mktemp)"; for ((i=0;i<n;i++)); do echo "${keys[$i]}=${ED[$i]}"; done > "$tc"
           do_preview "$tc"; rm -f "$tc"; pause ;;
      s|S) if [ -z "$EDNAME" ]; then read -rp "  Name this mode (one word): " EDNAME; EDNAME="${EDNAME// /}"; fi
           [ -z "$EDNAME" ] && { printf "  %sName required.%s\n" "$YEL" "$R"; pause; continue; }
           [ -n "$oldname" ] && [ "$oldname" != "$EDNAME" ] && remove_mode_line "$oldname"
           write_mode "$EDNAME" "$EDDESC" "$(ed_to_spec)"
           [ "$CURRENT_MODE" = "$oldname" ] && [ -n "$oldname" ] && CURRENT_MODE="$EDNAME"
           printf "\n  %sSaved mode '%s'.%s\n" "$GRN" "$EDNAME" "$R"; pause; return ;;
      *) for tok in $line; do
           if [[ "$tok" =~ ^[0-9]+$ ]] && [ "$tok" -ge 1 ] && [ "$tok" -le "$n" ]; then
             j=$((tok-1)); [ "${ED[$j]}" = 1 ] && ED[$j]=0 || ED[$j]=1
           fi
         done ;;
    esac
  done
}
save_current_as_mode() {     # snapshot live toggles into a new mode
  local nm ds i
  read -rp "  New mode name (one word): " nm; nm="${nm// /}"; [ -z "$nm" ] && return
  read -rp "  Short description: " ds
  for ((i=0;i<n;i++)); do ED[$i]="${state[$i]}"; done
  write_mode "$nm" "$ds" "$(ed_to_spec)"
  CURRENT_MODE="$nm"; save
  printf "\n  %sSaved mode '%s'.%s\n" "$GRN" "$nm" "$R"; pause
}

modes_menu() {
  local line idx i mark
  while true; do
    load_modes; clear
    printf '%s┌─ Modes ─────────────────────────────────────────────────┐%s\n' "$MAG" "$R"
    printf '%s  apply a preset, or create/edit one — all from here%s\n\n' "$DIM" "$R"
    for ((i=0;i<${#mode_names[@]};i++)); do
      mark="  "; [ "${mode_names[$i]}" = "$CURRENT_MODE" ] && mark="${GRN}▶${R} "
      printf "  %s%2d.%s %s%s%-9s%s %s%s%s\n" "$B" "$((i+1))" "$R" "$mark" "$CYN" "${mode_names[$i]}" "$R" "$DIM" "${mode_descs[$i]}" "$R"
    done
    printf '\n%sactive%s %s\n' "$B" "$R" "$(mode_status)"
    printf '%scommands%s  number=apply   eN=edit   c=create   dN=delete   s=save current   p=preview   b=back\n' "$B" "$R"
    read -rp $'\n> ' line
    case "$line" in
      b|B|'') return ;;
      c|C) edit_mode "" ;;
      s|S) save_current_as_mode ;;
      p|P) do_preview; pause ;;
      e*|E*) idx="${line#[eE]}"; idx="${idx// /}"
             [[ "$idx" =~ ^[0-9]+$ ]] && [ "$idx" -ge 1 ] && [ "$idx" -le "${#mode_names[@]}" ] && edit_mode "$((idx-1))" ;;
      d*|D*) idx="${line#[dD]}"; idx="${idx// /}"
             [[ "$idx" =~ ^[0-9]+$ ]] && [ "$idx" -ge 1 ] && [ "$idx" -le "${#mode_names[@]}" ] && delete_mode "$((idx-1))" ;;
      *) if [[ "$line" =~ ^[0-9]+$ ]] && [ "$line" -ge 1 ] && [ "$line" -le "${#mode_names[@]}" ]; then
           apply_mode "$((line-1))"; do_preview; pause
         fi ;;
    esac
  done
}

menu() {
  load_modes; clear
  printf '%s┌─ Claude Code status line ───────────────────────────────┐%s\n' "$CYN" "$R"
  printf '%s  toggle elements, or press m for modes (presets)%s\n' "$DIM" "$R"
  printf '%s  mode:%s %s\n\n' "$B" "$R" "$(mode_status)"
  local i box col
  for ((i=0;i<n;i++)); do
    if [ "${state[$i]}" = 1 ]; then box="${GRN}[✓]${R}"; col=""; else box="${DIM}[ ]${R}"; col="$DIM"; fi
    printf "  %s%2d.%s %s %s%-17s%s %s%s%s\n" "$B" "$((i+1))" "$R" "$box" "$col" "${labels[$i]}" "$R" "$DIM" "${shorts[$i]}" "$R"
  done
  printf '\n%scommands%s  number(s)=toggle  m=modes  a=all on  n=all off  ?N=explain  p=preview  q=quit\n' "$B" "$R"
}

seed_modes; load
while true; do
  menu
  read -rp $'\n> ' line
  case "$line" in
    q|Q|'') save; clear; printf '%sSaved.%s Status line updated — it refreshes automatically.\n' "$GRN" "$R"; do_preview; break ;;
    m|M) modes_menu ;;
    a|A) for ((i=0;i<n;i++)); do state[$i]=1; done; save ;;
    n|N) for ((i=0;i<n;i++)); do state[$i]=0; done; save ;;
    p|P) do_preview; pause ;;
    \?*) idx="${line#\?}"; idx="${idx// /}"
         if [[ "$idx" =~ ^[0-9]+$ ]] && [ "$idx" -ge 1 ] && [ "$idx" -le "$n" ]; then
           j=$((idx-1))
           printf '\n  %s%s%s — %s%s%s\n  %s\n' "$B" "${labels[$j]}" "$R" "$DIM" "${shorts[$j]}" "$R" "${longs[$j]}"
         else printf '\n  %sUnknown item.%s\n' "$YEL" "$R"; fi
         pause ;;
    *) for tok in $line; do
         if [[ "$tok" =~ ^[0-9]+$ ]] && [ "$tok" -ge 1 ] && [ "$tok" -le "$n" ]; then
           j=$((tok-1)); [ "${state[$j]}" = 1 ] && state[$j]=0 || state[$j]=1
         fi
       done; save ;;
  esac
done
