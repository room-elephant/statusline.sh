#!/bin/bash
set -euo pipefail

RAW_URL="https://raw.githubusercontent.com/JPedroBorges/statusline.sh/main/statusline.sh"
CLAUDE_DIR="$HOME/.claude"
TARGET="$CLAUDE_DIR/statusline.sh"
SETTINGS="$CLAUDE_DIR/settings.json"
STATUSLINE_JSON='{"type": "command", "command": "~/.claude/statusline.sh", "padding": 0}'

if ! command -v jq >/dev/null 2>&1; then
  echo "error: statusline.sh needs jq (https://jqlang.org). Install it and re-run." >&2
  exit 1
fi

mkdir -p "$CLAUDE_DIR"

# from a local checkout, copy; when piped via curl, download
SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]:-/}")
if [ -f "$SCRIPT_DIR/statusline.sh" ]; then
  cp "$SCRIPT_DIR/statusline.sh" "$TARGET"
else
  curl -fsSL "$RAW_URL" -o "$TARGET"
fi
chmod +x "$TARGET"
echo "installed $TARGET"

if [ ! -f "$SETTINGS" ]; then
  jq -n --argjson sl "$STATUSLINE_JSON" '{statusLine: $sl}' > "$SETTINGS"
  echo "created $SETTINGS with statusLine config"
elif [ "$(jq -r '.statusLine.command // ""' "$SETTINGS")" = "~/.claude/statusline.sh" ]; then
  echo "$SETTINGS already points at $TARGET — nothing to do"
elif [ "$(jq -r '.statusLine // ""' "$SETTINGS")" = "" ]; then
  cp "$SETTINGS" "$SETTINGS.bak"
  jq --argjson sl "$STATUSLINE_JSON" '.statusLine = $sl' "$SETTINGS.bak" > "$SETTINGS"
  echo "added statusLine to $SETTINGS (backup at $SETTINGS.bak)"
else
  echo "$SETTINGS already has a different statusLine config — not touching it."
  echo "To switch, set it to:"
  echo "  \"statusLine\": $STATUSLINE_JSON"
fi

echo "optional: create ~/.claude/statusline.conf to toggle segments (see README)"
echo "done — restart Claude Code (or open a new session) to see it"
