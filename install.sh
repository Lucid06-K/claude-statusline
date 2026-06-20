#!/usr/bin/env bash
# Install claude-statusline: symlink the scripts into ~/.claude so this repo
# stays the single source of truth (edit here, changes are live).
set -e

REPO="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.claude"
mkdir -p "$DEST"

for f in statusline-command.sh statusline-config.sh; do
  ln -sf "$REPO/$f" "$DEST/$f"
  echo "linked  $DEST/$f -> $REPO/$f"
done

cat <<'EOF'

Done. Two more steps to wire it up:

1) Status line — add to ~/.claude/settings.json:
     "statusLine": { "type": "command", "command": "bash ~/.claude/statusline-command.sh" }

2) Configurator alias — add to ~/.zshrc (or your shell rc):
     alias slconfig="bash ~/.claude/statusline-config.sh"

Then run  slconfig  to choose what shows.
EOF
