#!/usr/bin/env bash
# Apply / inspect status-line modes. Per-session by default (uses $CLAUDE_CODE_SESSION_ID),
# so each Claude Code session can show a different preset. Driven by the /mode slash command.
#
#   statusline-mode.sh <mode>          apply <mode> to THIS session (or global if no session)
#   statusline-mode.sh --global <mode> apply <mode> to the global default (all sessions)
#   statusline-mode.sh --list          list available modes
#   statusline-mode.sh --show          show the effective mode for this session
#   statusline-mode.sh --clear         drop this session's override (revert to global)

MODES="${HOME}/.claude/statusline.modes"
GLOBAL="${HOME}/.claude/statusline.conf"
SESSDIR="${HOME}/.claude/statusline.sessions"
KEYS="SL_DIRECTORY SL_GIT SL_MODEL SL_FASTMODE SL_EFFORT SL_CONTEXT SL_CONTEXT_WARN SL_RATELIMIT_5H SL_RATELIMIT_7D SL_BURNRATE SL_COST SL_COST_COLOR SL_ELAPSED SL_CLOCK"
sid="${CLAUDE_CODE_SESSION_ID:-}"

list_modes() { [ -f "$MODES" ] && grep -vE '^[[:space:]]*#' "$MODES" | awk -F'|' 'NF>=2{printf "  %-10s %s\n",$1,$2}'; }
resolve_spec() { awk -F'|' -v m="$1" '$1==m{print $3; exit}' "$MODES"; }
sess_conf() { printf '%s' "$SESSDIR/${sid}.conf"; }
effective_conf() { if [ -n "$sid" ] && [ -f "$(sess_conf)" ]; then sess_conf; else printf '%s' "$GLOBAL"; fi; }

write_conf() {   # $1 = mode name   $2 = target conf path
  local spec on=""
  spec=$(resolve_spec "$1")
  if [ -z "$spec" ]; then echo "Unknown mode: '$1'. Available:"; list_modes; return 1; fi
  case "$spec" in ALL) on="$KEYS";; NONE) on="";; *) on="$spec";; esac
  mkdir -p "$(dirname "$2")"
  { echo "# status line conf — managed by /mode"
    echo "SL_MODE=$1"
    local k; for k in $KEYS; do
      case " $on " in *" $k "*) echo "$k=1";; *) echo "$k=0";; esac
    done
  } > "$2"
  [ -d "$SESSDIR" ] && find "$SESSDIR" -name '*.conf' -mtime +7 -delete 2>/dev/null
  return 0
}
current_mode() { grep '^SL_MODE=' "$(effective_conf)" 2>/dev/null | head -1 | cut -d= -f2; }

case "${1:-}" in
  ""|--list|list)
    echo "Available modes:"; list_modes
    m=$(current_mode); echo; echo "This session: ${m:-custom}"
    ;;
  --show|show)
    m=$(current_mode); [ -z "$m" ] && m="(custom)"
    if [ -n "$sid" ] && [ -f "$(sess_conf)" ]; then echo "This session: $m  (per-session)"
    else echo "This session: $m  (global default)"; fi
    ;;
  --clear|clear|default|reset)
    if [ -n "$sid" ] && [ -f "$(sess_conf)" ]; then rm -f "$(sess_conf)"; echo "Reverted this session to the global default."
    else echo "This session already follows the global default."; fi
    ;;
  --global|-g)
    shift; [ -z "${1:-}" ] && { echo "Usage: --global <mode>"; exit 1; }
    write_conf "$1" "$GLOBAL" && echo "Global default set to '$1' (affects sessions without their own mode)."
    ;;
  *)
    if [ -n "$sid" ]; then
      write_conf "$1" "$(sess_conf)" && echo "This session is now using '$1' (applies on the next status line refresh)."
    else
      write_conf "$1" "$GLOBAL" && echo "No session id detected — set the global default to '$1'."
    fi
    ;;
esac
