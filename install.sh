#!/usr/bin/env bash
# Install claude-statusline. Run after cloning:  ./install.sh
# - symlinks the scripts into ~/.claude (this repo stays the source of truth)
# - installs the /mode slash command
# - wires the status line into ~/.claude/settings.json
# - adds the `slconfig` alias to your shell rc
# Re-running is safe (idempotent); existing files are backed up before changes.
set -e

REPO="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.claude"
mkdir -p "$DEST" "$DEST/commands"

command -v jq >/dev/null 2>&1 || { echo "error: 'jq' is required (brew install jq / apt install jq)"; exit 1; }

# 1) scripts -> symlinks
for f in statusline-command.sh statusline-config.sh statusline-mode.sh; do
  ln -sf "$REPO/$f" "$DEST/$f"
  echo "✓ linked  ~/.claude/$f"
done

# 2) /mode command
cp "$REPO/mode.md" "$DEST/commands/mode.md"
echo "✓ installed /mode command"

# 3) status line in settings.json (back up, then set .statusLine)
SETTINGS="$DEST/settings.json"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.bak"
tmp="$(mktemp)"
jq '.statusLine = {type:"command", command:"bash ~/.claude/statusline-command.sh"}' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
echo "✓ set statusLine in ~/.claude/settings.json (backup: settings.json.bak)"

# 4) slconfig alias in the shell rc
case "${SHELL##*/}" in
  bash) RC="$HOME/.bashrc" ;;
  *)    RC="$HOME/.zshrc"  ;;
esac
if ! grep -qs 'alias slconfig=' "$RC"; then
  printf '\n# claude-statusline configurator\nalias slconfig="bash ~/.claude/statusline-config.sh"\n' >> "$RC"
  echo "✓ added 'slconfig' alias to $RC"
else
  echo "• 'slconfig' alias already in $RC"
fi

cat <<EOF

Done 🎉
  • Restart Claude Code (or start a new session) to see the status line.
  • Reload your shell:  source $RC
  • Configure modes:    slconfig
  • Switch this session's mode inside Claude:  /mode
EOF
