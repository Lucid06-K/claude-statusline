#!/usr/bin/env bash
# Install claude-statusline: symlink the scripts into ~/.claude so this repo
# stays the single source of truth (edit here, changes are live).
set -e

REPO="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.claude"
mkdir -p "$DEST" "$DEST/commands"

for f in statusline-command.sh statusline-config.sh statusline-mode.sh; do
  ln -sf "$REPO/$f" "$DEST/$f"
  echo "linked  $DEST/$f -> $REPO/$f"
done

# /mode slash command (per-session mode switcher)
cp "$REPO/mode.md" "$DEST/commands/mode.md"
echo "installed /mode command -> $DEST/commands/mode.md"

cat <<'EOF'

Done. Two more steps to wire it up:

1) Status line — add to ~/.claude/settings.json:
     "statusLine": { "type": "command", "command": "bash ~/.claude/statusline-command.sh" }

2) Configurator alias — add to ~/.zshrc (or your shell rc):
     alias slconfig="bash ~/.claude/statusline-config.sh"

Then:
  • slconfig            choose the DEFAULT mode for new sessions (+ create/edit modes)
  • /mode <name>        switch THIS Claude session's mode (per-session)
  • /mode               list modes ·  /mode clear  revert to the default
EOF
