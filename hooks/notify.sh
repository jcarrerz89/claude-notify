#!/bin/bash
# =============================================================================
# notify.sh — Cross-platform notification hook for Claude Code
# =============================================================================
# Sends notifications to:
#   1. OS notification center (macOS, Linux, Windows)
#   2. Desktop dashboard app on localhost:9717 (if running)
#
# The notification title is derived from the project directory name.
# The message comes from Claude Code's actual prompt/question.
#
# Receives JSON via stdin from Claude Code's Notification hook:
#   { "title": "...", "message": "...", "notification_type": "..." }
#
# Also supports CLI args as fallback:
#   notify.sh [title] [message]
# =============================================================================

# Optional: profile gating (skip if run-with-profile.sh doesn't exist)
_profile_script="$(dirname "$0")/run-with-profile.sh"
if [ -f "$_profile_script" ]; then
  source "$_profile_script"
  require_profile "minimal" "notify"
fi

# --- Parse JSON from stdin ---
input=$(cat)
title=$(echo "$input" | jq -r '.title // empty' 2>/dev/null)
message=$(echo "$input" | jq -r '.message // empty' 2>/dev/null)
ntype=$(echo "$input" | jq -r '.notification_type // empty' 2>/dev/null)

# --- Detect client environment ---
CLIENT_PATH="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# Project name from directory (e.g. /Users/.../nogal -> Nogal)
PROJECT_NAME=$(basename "$CLIENT_PATH" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')

# Title = project name, Message = actual prompt from Claude Code
TITLE="${title:-${1:-${PROJECT_NAME:-Claude Code}}}"
MSG="${message:-${2:-Needs your attention}}"

# --- Detect client app ---
case "${TERM_PROGRAM:-}" in
  vscode)
    if [[ "${__CFBundleIdentifier:-}" == *"cursor"* ]]; then
      CLIENT="cursor"
      CLIENT_APP="Cursor"
    else
      CLIENT="vscode"
      CLIENT_APP="VS Code"
    fi
    ;;
  iTerm.app)
    CLIENT="terminal"
    CLIENT_APP="iTerm2"
    ;;
  Apple_Terminal)
    CLIENT="terminal"
    CLIENT_APP="Terminal"
    ;;
  *)
    CLIENT="terminal"
    CLIENT_APP="${TERM_PROGRAM:-Terminal}"
    ;;
esac

# --- 1. OS notification ---
case "$(uname -s)" in
  Darwin)
    osascript -e "display notification \"$MSG\" with title \"$TITLE\" sound name \"Ping\"" 2>/dev/null
    ;;
  Linux)
    if command -v notify-send &>/dev/null; then
      notify-send "$TITLE" "$MSG" 2>/dev/null
    elif command -v zenity &>/dev/null; then
      zenity --notification --text="$TITLE: $MSG" 2>/dev/null &
    fi
    ;;
  MINGW*|MSYS*|CYGWIN*)
    if command -v powershell.exe &>/dev/null; then
      powershell.exe -Command "[System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms'); [System.Windows.Forms.MessageBox]::Show('$MSG','$TITLE')" 2>/dev/null &
    fi
    ;;
esac

# --- 2. Desktop dashboard app (fire-and-forget) ---
DASHBOARD_PORT="${CLAUDE_NOTIFY_PORT:-9717}"
curl -s -X POST "http://localhost:${DASHBOARD_PORT}/notify" \
  -H "Content-Type: application/json" \
  -d "{\"title\":\"$TITLE\",\"message\":\"$MSG\",\"type\":\"$ntype\",\"source\":\"hook\",\"client\":\"$CLIENT\",\"client_app\":\"$CLIENT_APP\",\"client_path\":\"$CLIENT_PATH\"}" \
  --connect-timeout 1 &>/dev/null &

exit 0
