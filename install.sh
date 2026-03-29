#!/bin/bash
# =============================================================================
# install.sh — Install claude-notify into a Claude Code project
# =============================================================================
# Usage:
#   ./install.sh [target-project-dir]
#
# If no directory is provided, installs into the current directory.
#
# What it does:
#   1. Copies hooks/notify.sh into <project>/.claude/hooks/
#   2. Adds the Notification hook entry to <project>/.claude/settings.json
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_DIR="${1:-.}"
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

HOOKS_DIR="$TARGET_DIR/.claude/hooks"
SETTINGS_FILE="$TARGET_DIR/.claude/settings.json"

echo "Installing claude-notify into: $TARGET_DIR"

# --- 1. Copy notify.sh ---
mkdir -p "$HOOKS_DIR"
cp "$SCRIPT_DIR/hooks/notify.sh" "$HOOKS_DIR/notify.sh"
chmod +x "$HOOKS_DIR/notify.sh"
echo "  ✓ Copied notify.sh to $HOOKS_DIR/"

# --- 2. Update settings.json ---
if [ ! -f "$SETTINGS_FILE" ]; then
  # Create minimal settings.json with just the Notification hook
  cat > "$SETTINGS_FILE" <<'SETTINGS'
{
  "hooks": {
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/notify.sh"
          }
        ]
      }
    ]
  }
}
SETTINGS
  echo "  ✓ Created $SETTINGS_FILE with Notification hook"
else
  # Check if Notification hook already exists
  if command -v jq &>/dev/null && jq -e '.hooks.Notification' "$SETTINGS_FILE" &>/dev/null; then
    echo "  ⚠ Notification hook already exists in settings.json — skipping"
  elif command -v jq &>/dev/null; then
    # Add Notification hook to existing settings.json
    tmp=$(mktemp)
    jq '.hooks.Notification = [{"matcher": "", "hooks": [{"type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/notify.sh"}]}]' "$SETTINGS_FILE" > "$tmp"
    mv "$tmp" "$SETTINGS_FILE"
    echo "  ✓ Added Notification hook to $SETTINGS_FILE"
  else
    echo "  ⚠ jq not found — please manually add the Notification hook to $SETTINGS_FILE:"
    echo '    "Notification": [{"matcher": "", "hooks": [{"type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/notify.sh"}]}]'
  fi
fi

echo ""
echo "Done! Claude Code will now send notifications via:"
echo "  • OS notification center (macOS/Linux/Windows)"
echo "  • Desktop dashboard on localhost:\${CLAUDE_NOTIFY_PORT:-9717} (if running)"
