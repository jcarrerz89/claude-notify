#!/bin/bash
# =============================================================================
# install.sh — Install claude-notify notification hook
# =============================================================================
# Usage:
#   ./install.sh --global              Install globally (~/.claude/)
#   ./install.sh [target-project-dir]  Install into a specific project
#   ./install.sh                       Install into the current directory
#
# Global install:
#   Copies notify.sh to ~/.claude/hooks/ and wires the Notification hook in
#   ~/.claude/settings.json — fires for every Claude Code session on this machine.
#
# Project install:
#   Copies notify.sh to <project>/.claude/hooks/ and wires the hook in
#   <project>/.claude/settings.json — fires only for that project.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Parse args ---
GLOBAL=false
TARGET_DIR=""

for arg in "$@"; do
  case "$arg" in
    --global) GLOBAL=true ;;
    *)        TARGET_DIR="$arg" ;;
  esac
done

if $GLOBAL; then
  HOOKS_DIR="$HOME/.claude/hooks"
  SETTINGS_FILE="$HOME/.claude/settings.json"
  echo "Installing claude-notify globally into: $HOME/.claude/"
else
  TARGET_DIR="${TARGET_DIR:-.}"
  TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"
  HOOKS_DIR="$TARGET_DIR/.claude/hooks"
  SETTINGS_FILE="$TARGET_DIR/.claude/settings.json"
  echo "Installing claude-notify into: $TARGET_DIR"
fi

# --- 1. Copy notify.sh ---
mkdir -p "$HOOKS_DIR"
cp "$SCRIPT_DIR/hooks/notify.sh" "$HOOKS_DIR/notify.sh"
chmod +x "$HOOKS_DIR/notify.sh"
echo "  ✓ Copied notify.sh to $HOOKS_DIR/"

# --- 2. Update settings.json ---
HOOK_COMMAND="\"$HOOKS_DIR/notify.sh\""

if [ ! -f "$SETTINGS_FILE" ]; then
  mkdir -p "$(dirname "$SETTINGS_FILE")"
  cat > "$SETTINGS_FILE" <<SETTINGS
{
  "hooks": {
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": $HOOK_COMMAND
          }
        ]
      }
    ]
  }
}
SETTINGS
  echo "  ✓ Created $SETTINGS_FILE with Notification hook"
else
  if command -v jq &>/dev/null && jq -e '.hooks.Notification' "$SETTINGS_FILE" &>/dev/null; then
    echo "  ⚠ Notification hook already exists in settings.json — skipping"
  elif command -v jq &>/dev/null; then
    tmp=$(mktemp)
    jq --arg cmd "$HOOKS_DIR/notify.sh" \
      '.hooks.Notification = [{"matcher": "", "hooks": [{"type": "command", "command": $cmd}]}]' \
      "$SETTINGS_FILE" > "$tmp"
    mv "$tmp" "$SETTINGS_FILE"
    echo "  ✓ Added Notification hook to $SETTINGS_FILE"
  else
    echo "  ⚠ jq not found — please manually add to $SETTINGS_FILE:"
    echo "    \"Notification\": [{\"matcher\": \"\", \"hooks\": [{\"type\": \"command\", \"command\": \"$HOOKS_DIR/notify.sh\"}]}]"
  fi
fi

echo ""
if $GLOBAL; then
  echo "Done! claude-notify is now active for all Claude Code sessions on this machine."
else
  echo "Done! claude-notify is now active for this project."
fi
echo ""
echo "Notifications will be sent to:"
echo "  • OS notification center (macOS/Linux/Windows)"
echo "  • Desktop dashboard on localhost:\${CLAUDE_NOTIFY_PORT:-9717} (if running)"
