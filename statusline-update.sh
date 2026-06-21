#!/usr/bin/env bash
# Update claude-statusline. The scripts are symlinked from the git checkout, so updating
# is a fast-forward `git pull` of that repo — pinned to its HTTPS origin, never sudo.
#
#   statusline-update.sh            check + update to the latest (interactive output)
#   statusline-update.sh --check    quiet: exit 0 = up to date, 10 = behind, 1 = can't tell
#   statusline-update.sh --background  used by the daily auto-check (silent; pulls if behind)
#   statusline-update.sh --auto on|off  enable/disable the once-a-day background auto-update
#   statusline-update.sh --status   print version + auto-update state
set -u

SELF="${HOME}/.claude/statusline-command.sh"
AUTOFLAG="${HOME}/.claude/statusline.auto-update"   # presence = auto-update enabled

# Resolve the repo directory from the (possibly symlinked) installed script.
_real="$SELF"; [ -L "$SELF" ] && _real="$(readlink "$SELF")"
case "$_real" in /*) ;; *) _real="$(dirname "$SELF")/$_real" ;; esac
REPO="$(cd "$(dirname "$_real")" 2>/dev/null && pwd || true)"

is_git() { [ -n "$REPO" ] && git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; }
cur_ver() { [ -f "$REPO/VERSION" ] && tr -d '[:space:]' < "$REPO/VERSION" || echo "?"; }
cur_rev() { git -C "$REPO" log -1 --format='%h %cd' --date=short 2>/dev/null; }

behind_count() {                      # echo commits behind origin's default branch
  local br; br="$(git -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null)"; br="${br:-main}"
  git -C "$REPO" fetch --quiet origin 2>/dev/null || return 1
  git -C "$REPO" rev-list --count "HEAD..origin/${br}" 2>/dev/null || echo 0
}

apply() {                             # fast-forward pull, then syntax-check the result
  local br; br="$(git -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null)"; br="${br:-main}"
  git -C "$REPO" pull --ff-only --quiet origin "$br" 2>/dev/null || {
    echo "  ✗ pull failed — you may have local changes. Check: git -C \"$REPO\" status"; return 1; }
  local f
  for f in statusline-command.sh statusline-config.sh statusline-mode.sh statusline-update.sh; do
    bash -n "$REPO/$f" 2>/dev/null || { echo "  ✗ syntax error in $f after update (not loaded)"; return 1; }
  done
  # Refresh the symlinks so updates self-heal: picks up new/renamed scripts and
  # converts older copy-based installs (e.g. the /mode command) to live symlinks.
  local s
  for s in "$REPO"/statusline-*.sh; do ln -sf "$s" "${HOME}/.claude/$(basename "$s")" 2>/dev/null; done
  [ -f "$REPO/mode.md" ] && { mkdir -p "${HOME}/.claude/commands"; ln -sf "$REPO/mode.md" "${HOME}/.claude/commands/mode.md" 2>/dev/null; }
  return 0
}

case "${1:-}" in
  --check)
    is_git || { echo "not a git checkout"; exit 1; }
    n="$(behind_count)" || { echo "offline"; exit 1; }
    if [ "${n:-0}" -gt 0 ]; then echo "$n update(s) available"; exit 10; else echo "up to date"; exit 0; fi ;;

  --background)                       # daily auto-check (already throttled by the caller)
    [ -f "$AUTOFLAG" ] || exit 0
    is_git || exit 0
    n="$(behind_count)" || exit 0
    [ "${n:-0}" -gt 0 ] && apply >/dev/null 2>&1
    exit 0 ;;

  --auto)
    case "${2:-}" in
      on)  : > "$AUTOFLAG"; echo "Auto-update ON — checks once a day in the background." ;;
      off) rm -f "$AUTOFLAG"; echo "Auto-update OFF." ;;
      *)   [ -f "$AUTOFLAG" ] && echo "Auto-update is ON" || echo "Auto-update is OFF" ;;
    esac ;;

  --status)
    if is_git; then echo "claude-statusline $(cur_ver) — $(cur_rev)"; else echo "claude-statusline $(cur_ver) (not a git checkout)"; fi
    [ -f "$AUTOFLAG" ] && echo "auto-update: on" || echo "auto-update: off" ;;

  *)
    is_git || { echo "Not a git checkout. Reinstall from https://github.com/Lucid06-K/claude-statusline"; exit 1; }
    echo "Checking for updates…  (current: $(cur_ver), $(cur_rev))"
    n="$(behind_count)" || { echo "Couldn't reach GitHub — offline?"; exit 1; }
    if [ "${n:-0}" -eq 0 ]; then echo "Already up to date."; exit 0; fi
    echo "$n new commit(s) available. Updating…"
    if apply; then echo "✓ Updated to $(cur_ver) ($(cur_rev)). Restart Claude Code to load it."; else exit 1; fi ;;
esac
